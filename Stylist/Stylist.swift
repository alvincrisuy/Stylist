//
//  Stylist.swift
//  Stylist
//
//  Created by Yonas Kolb on 18/8/17.
//  Copyright © 2017 Stylist. All rights reserved.
//

import Foundation
import KZFileWatchers

public class Stylist {

    public static let shared = Stylist()

    var fileWatchers: [FileWatcherProtocol] = []

    var viewStyles: [String: [WeakContainer<NSObject>]] = [:]

    var properties: [StyleProperty] = []

    public var themes: [String: Theme] = [:]

    init() {
        properties += StyleProperties.view
    }

    public func addProperty<ViewType, PropertyType>(_ name: String, viewType: ViewType.Type, propertyType: PropertyType.Type, _ style: @escaping (ViewType, PropertyValue<PropertyType>) -> Void) {
        properties.append(StyleProperty(name: name, style: style))
    }

    public func addProperty<ViewType, PropertyType>(_ name: String, _ style: @escaping (ViewType, PropertyValue<PropertyType>) -> Void) {
        properties.append(StyleProperty(name: name, style: style))
    }


    public func addProperty(_ property: StyleProperty) {
        properties.append(property)
    }

    func clear() {
        viewStyles = [:]
    }

    func setStyles(view: NSObject, styles: [String]) {
        for style in styles {
            var views: [WeakContainer<NSObject>]
            if let existingViews = viewStyles[style] {
                views = existingViews.filter{ $0.value != nil }
            } else {
                views = []
            }

            if !views.contains(where: { $0.value! === view}) {
                views.append(WeakContainer(view))
            }
            viewStyles[style] = views
        }

        for theme in themes.values {
            for style in styles {
                if let style = theme.getStyle(style) {
                    apply(view: view, style: style)
                }
            }
        }
    }

    func apply(view: Any, style: Style) {
        for styleProperty in style.properties {

            guard styleProperty.context.isValidDevice else { continue }

            let properties = getValidProperties(name: styleProperty.name, view: view)
            for property in properties {
                do {
                    try property.apply(view, styleProperty)
                } catch {
                    print("Error applying property: \(error)")
                }
            }
        }
        if let view = view as? View, let parent = view.superview, let parentStyle = style.parentStyle {
            apply(view: parent, style: parentStyle)
        }
    }

    func getValidProperties(name: String, view: Any) -> [StyleProperty] {
        return properties.filter { $0.canStyle(name: name, view: view) }
    }

    func getStyles(view: NSObject) -> [String] {
        var styles: [String] = []
        for (style, views) in viewStyles {
            for viewContainer in views {
                if let value = viewContainer.value, value === view {
                    styles.append(style)
                }
            }
        }
        return styles
    }

    func apply(theme: Theme) {
        for style in theme.styles {
            if let views = viewStyles[style.name] {
                for view in views.flatMap({$0.value}) {
                    apply(view: view, style: style)
                }
            }
            for property in style.properties {
                if !properties.contains(where: {$0.name == property.name}) {
                    print("Theme contains unknown property: \(property.name)")
                }
            }
        }
    }


    /// Loads a Theme from a file
    ///
    /// - Parameter path: the path to the file. Can be either a yaml or json file
    /// - Throws: throws if the file is not found or parsing fails
    public func load(path: String) throws {
        let theme = try Theme(path: path)
        self.themes[path] = theme
        apply(theme: theme)
    }


    /// Watch a Theme file and automatically reload and applies if there are changes
    ///
    /// - Parameters:
    ///   - url: the url to the Theme. This can be a local file url or a remote url
    ///   - animateChanges: whether to apply a small UIView animation when new changes are applied
    ///   - parsingError: is called if there was an error parsing the theme. 
    ///     It contains finge grained info about why the theme was invalid
    /// - Returns: The file watcher, which can later be stopped
    /// - Throws: An error is thrown if the file couldn't be watched
    @discardableResult
    public func watch(url: URL, animateChanges: Bool = true, parsingError: @escaping (ThemeError) -> Void) -> FileWatcherProtocol {
        let fileWatcher: FileWatcherProtocol
        if url.isFileURL {
            fileWatcher = FileWatcher.Local(path: url.path)
        } else {
            fileWatcher = FileWatcher.Remote(url: url)
        }

        let stylist = self
        do {
            try fileWatcher.start() { result in
                switch result {
                case .noChanges:
                    break
                case .updated(let data):
                    do {
                        let theme = try Theme(data: data)
                        self.themes[url.path] = theme
                        if animateChanges {
                            UIView.animate(withDuration: 0.2) {
                                stylist.apply(theme: theme)
                            }
                        } else {
                            stylist.apply(theme: theme)
                        }
                    } catch let error as ThemeError {
                        parsingError(error)
                    } catch {
                        // unknown error occured
                    }
                }
            }
        } catch {
            parsingError(ThemeError.notFound)
        }
        return fileWatcher
    }
}

struct WeakContainer<T> where T: AnyObject {
    weak var value : T?

    init(_ value: T) {
        self.value = value
    }
}
