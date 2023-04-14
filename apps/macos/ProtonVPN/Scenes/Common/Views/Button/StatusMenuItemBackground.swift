//
//  StatusMenuItemBackground.swift
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
import Theme
import Theme_macOS

class StatusMenuItemBackground: HoverDetectionButtonAdvanced {
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    
    override func viewWillDraw() {
        super.viewWillDraw()
        
        let style: AppTheme.Style
        if isHovered {
            style = .weak
        } else {
            style = .transparent
        }
        
        layer?.backgroundColor = .cgColor(.background, style)
    }
}
