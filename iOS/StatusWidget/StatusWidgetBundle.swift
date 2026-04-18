//
//  StatusWidgetBundle.swift
//  StatusWidget
//
//  Created by Fokke Zandbergen on 13/04/2026.
//

import SwiftUI
import WidgetKit

@main
struct StatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        StatusMetricWidget()
    }
}
