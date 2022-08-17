//
//  FunctionConstants.swift
//  SPIRV-Cross
//
//  Created by Thomas Roughton on 6/06/19.
//

import Foundation
import SPIRV_Cross

enum FunctionConstantValue : Hashable, CustomStringConvertible {
    case float(Float)
    case int32(Int32)
    case uint32(UInt32)
    case bool(Bool)
    
    var description : String {
        switch self {
        case .float(let value):
            return value.description
        case .int32(let value):
            return value.description
        case .uint32(let value):
            return value.description
        case .bool(let value):
            return value .description
        }
    }
}

struct FunctionConstant : Hashable {
    let name : String
    let type : SPIRVType
    let value : FunctionConstantValue?
    let index : Int
    
    init(name: String, type: SPIRVType, value: FunctionConstantValue?, index: Int) {
        self.name = name
        self.type = type
        self.value = value
        self.index = index
    }
    
    init(constant: spvc_specialization_constant, compiler: SPIRVCompiler) {
        self.name = String(cString: spvc_compiler_get_name(compiler.compiler, constant.id))
        
        let constantHandle = spvc_compiler_get_constant_handle(compiler.compiler, constant.id)
        self.type = SPIRVType(compiler: compiler.compiler, typeId: spvc_constant_get_type(constantHandle))
        
        switch self.type {
        case .float:
            self.value = .float(spvc_constant_get_scalar_fp32(constantHandle, 0, 0))
        case .int8:
            self.value = .int32(spvc_constant_get_scalar_i8(constantHandle, 0, 0))
        case .int16:
            self.value = .int32(spvc_constant_get_scalar_i16(constantHandle, 0, 0))
        case .int32:
            self.value = .int32(spvc_constant_get_scalar_i32(constantHandle, 0, 0))
        case .uint8:
            self.value = .uint32(spvc_constant_get_scalar_u8(constantHandle, 0, 0))
        case .uint16:
            self.value = .uint32(spvc_constant_get_scalar_u16(constantHandle, 0, 0))
        case .uint32:
            self.value = .uint32(spvc_constant_get_scalar_u32(constantHandle, 0, 0))
        case .bool:
            self.value = .bool(spvc_constant_get_scalar_i8(constantHandle, 0, 0) > 0)
        default:
            fatalError()
        }
        
        self.index = Int(constant.constant_id)
    }
}
