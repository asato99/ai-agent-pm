// Sources/App/Core/Extensions/TypeAliases.swift
// 型エイリアスの定義
//
// Domain.Task と Swift.Task の名前衝突について:
// 各ビューファイルでは private typealias を使って解決しています。
// - private typealias AsyncTask = _Concurrency.Task
// - task.description などは非オプショナルのため、if let ではなく直接使用

import Foundation
import Domain
