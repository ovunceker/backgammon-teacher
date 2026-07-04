# Graph Report - Backgammon Teacher  (2026-07-04)

## Corpus Check
- 21 files · ~16,597 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 297 nodes · 711 edges · 11 communities (10 shown, 1 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4b5a12a2`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_MoveExplainer & Tests|MoveExplainer & Tests]]
- [[_COMMUNITY_Board State & Encoding|Board State & Encoding]]
- [[_COMMUNITY_Board View Rendering|Board View Rendering]]
- [[_COMMUNITY_Game View Model|Game View Model]]
- [[_COMMUNITY_Explanation Renderer & UI|Explanation Renderer & UI]]
- [[_COMMUNITY_Explanation Reasons|Explanation Reasons]]
- [[_COMMUNITY_Python Game Worker|Python Game Worker]]
- [[_COMMUNITY_AI Player & Evaluation|AI Player & Evaluation]]
- [[_COMMUNITY_TDGammon ML Package|TDGammon ML Package]]
- [[_COMMUNITY_App Entry & SwiftUI|App Entry & SwiftUI]]
- [[_COMMUNITY_Board Geometry Shapes|Board Geometry Shapes]]

## God Nodes (most connected - your core abstractions)
1. `MoveExplainerTests` - 78 edges
2. `PositionFeatures` - 45 edges
3. `GameViewModel` - 44 edges
4. `ExplanationReason` - 27 edges
5. `BoardView` - 21 edges
6. `BoardState` - 18 edges
7. `MoveAnalysis` - 14 edges
8. `CheckerFlightOverlay` - 13 edges
9. `FlightInfo` - 13 edges
10. `Player` - 13 edges

## Surprising Connections (you probably didn't know these)
- `ContentView` --calls--> `GameViewModel`  [INFERRED]
  Backgammon Teacher/ContentView.swift → Backgammon Teacher/GameViewModel.swift
- `BoardView` --references--> `MoveAnalysis`  [EXTRACTED]
  Backgammon Teacher/BoardView.swift → Backgammon Teacher/MoveExplainer.swift
- `severityColor()` --references--> `ErrorSeverity`  [EXTRACTED]
  Backgammon Teacher/BoardView.swift → Backgammon Teacher/MoveExplainer.swift
- `ExplanationSheet` --references--> `MoveAnalysis`  [EXTRACTED]
  Backgammon Teacher/BoardView.swift → Backgammon Teacher/MoveExplainer.swift
- `GameViewModel` --references--> `MoveAnalysis`  [EXTRACTED]
  Backgammon Teacher/GameViewModel.swift → Backgammon Teacher/MoveExplainer.swift

## Import Cycles
- None detected.

## Communities (11 total, 1 thin omitted)

### Community 0 - "MoveExplainer & Tests"
Cohesion: 0.06
Nodes (5): Backgammon_Teacher, PositionFeatures, MoveExplainerTests, XCTest, XCTestCase

### Community 1 - "Board State & Encoding"
Cohesion: 0.13
Nodes (15): BoardEncoder, BoardState, Player, black, white, Dice, FlightInfo, CheckerMove (+7 more)

### Community 2 - "Board View Rendering"
Cohesion: 0.14
Nodes (18): BoardView, CheckerFlightOverlay, DiceFaceView, PC, PointTriangle, PointView, SettingsView, severityColor() (+10 more)

### Community 3 - "Game View Model"
Cohesion: 0.14
Nodes (4): GameViewModel, CheckerMove, Set, Task

### Community 4 - "Explanation Renderer & UI"
Cohesion: 0.13
Nodes (9): ExplanationSheet, ExplanationRenderer, RenderedExplanation, ErrorSeverity, blunder, error, fine, inaccuracy (+1 more)

### Community 5 - "Explanation Reasons"
Cohesion: 0.10
Nodes (16): ExplanationReason, badHit, bearOffSafety, brokenAnchor, exposureDifference, generallyBetter, homeBoardWeakened, missedHit (+8 more)

### Community 6 - "Python Game Worker"
Cohesion: 0.18
Nodes (19): apply_move(), _apply_step(), _bear_off_ok_black(), _bear_off_ok_white(), _can_bear_off_black(), _can_bear_off_white(), _choose_1ply_cpu(), encode_board() (+11 more)

### Community 7 - "AI Player & Evaluation"
Cohesion: 0.19
Nodes (11): AIPlayer, MoveAnalysis, Blot, BoardState, CoreML, Equatable, Float, Foundation (+3 more)

### Community 8 - "TDGammon ML Package"
Cohesion: 0.14
Nodes (13): author, description, name, path, author, description, name, path (+5 more)

### Community 9 - "App Entry & SwiftUI"
Cohesion: 0.25
Nodes (5): App, Backgammon_TeacherApp, ContentView, Scene, SwiftUI

## Knowledge Gaps
- **33 isolated node(s):** `CoreML`, `fine`, `inaccuracy`, `error`, `blunder` (+28 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameViewModel` connect `Game View Model` to `Board State & Encoding`, `Board View Rendering`, `Explanation Renderer & UI`, `Explanation Reasons`, `AI Player & Evaluation`, `App Entry & SwiftUI`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `PositionFeatures` connect `MoveExplainer & Tests` to `Board State & Encoding`, `Game View Model`, `Explanation Reasons`, `AI Player & Evaluation`?**
  _High betweenness centrality (0.155) - this node is a cross-community bridge._
- **Why does `MoveExplainerTests` connect `MoveExplainer & Tests` to `Explanation Renderer & UI`, `Explanation Reasons`?**
  _High betweenness centrality (0.139) - this node is a cross-community bridge._
- **Are the 37 inferred relationships involving `PositionFeatures` (e.g. with `.detectReasons()` and `.testBlotAtSingleCheckerPoint()`) actually correct?**
  _`PositionFeatures` has 37 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `ExplanationReason` (e.g. with `.testMissedHitDetected()` and `.testMissedHitHasHigherPriorityThanUnnecessaryBlot()`) actually correct?**
  _`ExplanationReason` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `CoreML`, `fine`, `inaccuracy` to the rest of the system?**
  _33 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `MoveExplainer & Tests` be split into smaller, more focused modules?**
  _Cohesion score 0.055288461538461536 - nodes in this community are weakly interconnected._