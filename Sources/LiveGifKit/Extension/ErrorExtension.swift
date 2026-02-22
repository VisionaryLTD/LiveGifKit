//
//  File.swift
//
//
//  Created by tangxiaojun on 2023/12/15.
//

import Foundation

public enum GifError: Error {
    case unableToReadFile
    case unableToFindTrack
    case unableToCreateOutput
    case unknown
    case unableToFindvideoUrl
    case gifResultNil
    case tooManyFrames
    case invalidImageData
    case unableToRemoveBackground
    case unsupportedSource
    case unimplemented
}

public enum AlbumToolError: Error {
    case unAuthorized
    case saveFail
    case denied
    case notDetermined
    case limited
    case unknown
}

public typealias GIFError = GifError

extension AlbumToolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .denied:
            return "Photos access is denied."
        case .notDetermined:
            return "Photos access is not determined yet."
        case .saveFail:
            return "Failed to save GIF to Photos."
        case .limited:
            return "Photos access is limited."
        case .unAuthorized:
            return "Photos access is unauthorized."
        case .unknown:
            return "An unknown Photos error occurred."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .denied, .unAuthorized:
            return "Allow Photos access in System Settings > Privacy & Security > Photos."
        case .notDetermined:
            return "Please try again and allow Photos access when prompted."
        case .saveFail, .limited, .unknown:
            return nil
        }
    }
}
