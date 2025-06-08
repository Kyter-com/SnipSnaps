//
//  Photos.swift
//  SnipSnaps
//
//  Created by Nick Reisenauer on 6/7/25.
//

import Photos

func getPhotoAuthStatus() -> Bool {
  let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
  return status == .authorized
}
