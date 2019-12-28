//
//  File.swift
//  
//
//  Created by Thomas Roughton on 3/12/19.
//

import SPIRV_Cross

struct PushConstant : Hashable {
    let name : String
    let type : SPIRVType
    let range : Range<Int>
}
