//
//  Copyright © Uber Technologies, Inc. All rights reserved.
//

import UIKit

class ThemeEditorViewController: ViewController<ThemeEditorView>,
UITableViewDelegate,
UITableViewDataSource,
ColorEditorListener{
    
    let theme: Theme
    let resources: Resources
    let preferences: Preferences

    private let reuseID = "reuseID"
    
    enum Section: Int {
        
        case theme
        case resource
        
        init(from rawValue: Int) {
            if let new = Section(rawValue: rawValue) {
                self = new
            } else {
                fatalError("Invalid Section Index: \"\(rawValue)\"")
            }
        }
    }
    
    init(preferences: Preferences) {
        self.preferences = preferences
        self.theme = preferences.theme
        self.resources = preferences.resources
        super.init(viewCreator: ThemeEditorView.init)
    }
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        switch Section(from: section) {
        case .theme: return theme.colors.count
        case .resource: return resources.colors.count
        }
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID, for: indexPath)
        cell.textLabel?.text = provider(for: indexPath).colors[indexPath.row].name
        return cell
    }
    
    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        let provider = self.provider(for: indexPath)
        let color = provider.colors[indexPath.row]
        showColorEditor(for: color,
                        in: provider)
    }
    
    func provider(for indexPath: IndexPath) -> ColorProvider {
        switch Section(from: indexPath.section) {
        case .theme: return theme
        case .resource: return resources
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        specializedView.table.register(UITableViewCell.self,
                                       forCellReuseIdentifier: reuseID)
        specializedView.table.dataSource = self
        specializedView.table.delegate = self
        specializedView.addButton.addTarget(self,
                                            action: #selector(addNewColorPressed),
                                            for: .touchUpInside)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        specializedView.table.reloadData()
    }
    
    @objc
    func addNewColorPressed() {
        let bottomSheet = UIAlertController(title: "Where Should the Color be Added?",
                                            message: "",
                                            preferredStyle: .actionSheet)
        func showEditor(for provider: ColorProvider) -> (UIAlertAction) -> () {
            return { (action) in
                self.showColorEditor(for: NamedColor(name: "",
                                                     hex: 0),
                                     in: provider)
            }
        }
        bottomSheet.addAction(UIAlertAction(title: "Theme",
                                            style: .default,
                                            handler: showEditor(for: theme)))
        bottomSheet.addAction(UIAlertAction(title: "Resource",
                                            style: .default,
                                            handler: showEditor(for: resources)))
        present(bottomSheet, animated: true, completion: nil)
    }
    
    private func showColorEditor(for color: NamedColor,
                                 in provider: ColorProvider) {
        let colorEditorViewController = ColorEditorViewController(color: color,
                                                                  in: provider)
        colorEditorViewController.listener = self
        navigationController
            .orAssert("This view controller requires a navigation controller to function correctly")?
            .pushViewController(colorEditorViewController,
                                animated: true)
    }
    
    func finishedEditingColor(_ color: NamedColor) {
        
    }
    
}

class ThemeEditorView: View {
    
    let addButton: Button = {
        let button = Button()
        button.setTitle("Add new Color",
                        for: .normal)
        return button
    }()
    
    let table = UITableView()
    
    override init() {
        super.init()
        addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint
            .activate([
                table.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                table.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
                table.topAnchor.constraint(equalTo: topAnchor),
                table.bottomAnchor.constraint(equalTo: bottomAnchor),
                addButton.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
                addButton.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
                addButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
                ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
//        let oldInsets = table.contentInset
//        table.contentInset = .init(top: oldInsets.top,
//                                   left: oldInsets.bottom,
//                                   bottom: -(table.frame.height - addButton.frame.minY),
//                                   right: oldInsets.right)
    }
    
}