"""Convert trained tdgammon.pt -> TDGammon.mlpackage via MIL builder.

Bypasses the torch frontend (which segfaults under torch 2.10 + coremltools 9)
by building the mlprogram directly from the weight matrices. Keeps the Swift
contract: input feature "x" (1x200), output feature "output" (1x6).
"""
import sys
import numpy as np
import torch

print("step 1: load weights", flush=True)
import json, pathlib
prov_path = pathlib.Path("tdgammon.pt.json")
if prov_path.exists():
    prov = json.loads(prov_path.read_text())
    print(f"  provenance: {prov}", flush=True)
else:
    print("  WARNING: tdgammon.pt.json not found — checkpoint predates provenance "
          "tracking; engine version unknown.", flush=True)
sd = torch.load("tdgammon.pt", map_location="cpu")
W1 = sd["net.0.weight"].numpy().astype(np.float32)   # (160,200)
b1 = sd["net.0.bias"].numpy().astype(np.float32)     # (160,)
W2 = sd["net.2.weight"].numpy().astype(np.float32)   # (6,160)
b2 = sd["net.2.bias"].numpy().astype(np.float32)     # (6,)
print("  shapes:", W1.shape, b1.shape, W2.shape, b2.shape, flush=True)

print("step 2: import coremltools", flush=True)
import coremltools as ct
from coremltools.converters.mil import Builder as mb
print("  coremltools", ct.__version__, flush=True)

print("step 3: build MIL program", flush=True)


@mb.program(input_specs=[mb.TensorSpec(shape=(1, 200))])
def prog(x):
    h = mb.linear(x=x, weight=W1, bias=b1)
    h = mb.sigmoid(x=h)
    o = mb.linear(x=h, weight=W2, bias=b2)
    o = mb.sigmoid(x=o, name="output")
    return o


print("step 4: convert to mlprogram", flush=True)
mlmodel = ct.convert(prog, convert_to="mlprogram",
                     compute_precision=ct.precision.FLOAT32,  # exact parity; FP16 default wobbles ~0.002
                     inputs=[ct.TensorType(name="x", shape=(1, 200))])

print("step 5: save", flush=True)
mlmodel.save("TDGammon_new.mlpackage")
print("  saved TDGammon_new.mlpackage", flush=True)

print("step 6: numerical parity vs PyTorch", flush=True)
import torch.nn as nn


class M(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(200, 160), nn.Sigmoid(),
                                 nn.Linear(160, 6), nn.Sigmoid())

    def forward(self, x):
        return self.net(x)


m = M()
m.load_state_dict(sd)
m.eval()
rng = np.random.default_rng(0)
xt = rng.standard_normal((1, 200)).astype(np.float32)
with torch.no_grad():
    torch_out = m(torch.from_numpy(xt)).numpy().ravel()
cm_out = np.array(mlmodel.predict({"x": xt})["output"]).ravel()
print("  torch :", np.round(torch_out, 5), flush=True)
print("  coreml:", np.round(cm_out, 5), flush=True)
print("  max abs diff:", float(np.max(np.abs(torch_out - cm_out))), flush=True)
print("DONE", flush=True)
