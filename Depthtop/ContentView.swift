//
//  ContentView.swift
//  Depthtop
//
//  Created by Brandon Winston on 8/22/25.
//

import SwiftUI

struct ContentView: View {

    var body: some View {
        VStack {
            Text("Hello, world!")

            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
