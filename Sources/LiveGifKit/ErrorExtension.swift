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
}

public enum AlbumToolError: Error {
    case unAuthorized
    case saveFail
    case denied
    case notDetermined
    case limited
    case unknown
}
