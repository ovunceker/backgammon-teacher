//
//  ContentView.swift
//  Backgammon Teacher
//
//  Created by Ovunc Ozgun Eker on 5/23/26.
//

import SwiftUI

struct ContentView: View {
    @State private var vm = GameViewModel()

    var body: some View {
        BoardView()
            .environment(vm)
    }
}

#Preview {
    ContentView()
}
