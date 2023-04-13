//
//  LoadCircle.swift
//  ProtonVPN - Created on 27.06.19.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of ProtonVPN.
//
//  ProtonVPN is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonVPN is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonVPN.  If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa
import Theme_macOS

class LoadCircle: NSView {
    var load: Int? {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let load = load else {
            return
        }
        
        // inner circle
        let icb = CGRect(x: 1.5, y: 1.5, width: bounds.width - 3, height: bounds.height - 3)
        context.setLineWidth(1.0)
        context.addEllipse(in: icb)
        context.setStrokeColor(.cgColor(.icon, .hint))
        context.drawPath(using: .stroke)
        
        // outer circle segment
        let ocb = CGRect(x: 1, y: 1, width: bounds.width - 2, height: bounds.height - 2)
        let startAngle: CGFloat = .pi / 2
        let loadPortion = load > 15 ? load : 15
        let endAngle: CGFloat = (CGFloat(loadPortion) / 100) * (-2 * .pi) + .pi / 2
        context.setLineWidth(2.0)

        let circleStyle: AppTheme.Style
        if load < 76 {
            circleStyle = .success
        } else if load < 91 {
            circleStyle = .warning
        } else {
            circleStyle = .danger
        }
        context.setStrokeColor(.cgColor(.icon, circleStyle))

        context.addArc(center: CGPoint(x: (ocb.width / 2) + ocb.origin.x, y: (ocb.height / 2) + ocb.origin.y),
                       radius: ocb.width / 2,
                       startAngle: startAngle,
                       endAngle: endAngle,
                       clockwise: true)
        context.drawPath(using: .stroke)
    }
}
