//
//  MainMenuView.swift
//  lego-morts-one-3d
//
//  Title screen: New Game / Continue / Settings over a horror city art panel.
//  Continue lists every playthrough you can resume.
//

import UIKit

final class MainMenuView: UIView {

    var onNewGame: (() -> Void)?
    var onContinueSlot: ((SaveGameStore.Slot) -> Void)?
    var onSettings: (() -> Void)?

    private let artView = MenuArtView()
    private let titleLabel = UILabel()
    private let continueButton = UIButton(type: .system)
    private let settingsPanel = UIView()
    private let settingsLabel = UILabel()
    private let savesPanel = UIView()
    private let savesStack = UIStackView()
    private let savesScroll = UIScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshContinue() {
        let has = !SaveGameStore.continuableSlots().isEmpty
        continueButton.isEnabled = has
        continueButton.alpha = has ? 1 : 0.35
    }

    private func setup() {
        artView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artView)

        titleLabel.text = "LEGO MORTS ONE"
        titleLabel.font = .systemFont(ofSize: 34, weight: .black)
        titleLabel.textColor = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let newGame = makeButton("New Game")
        newGame.addTarget(self, action: #selector(tapNew), for: .touchUpInside)

        continueButton.setTitle("Continue", for: .normal)
        style(continueButton)
        continueButton.addTarget(self, action: #selector(tapContinue), for: .touchUpInside)

        let settings = makeButton("Settings")
        settings.addTarget(self, action: #selector(tapSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [newGame, continueButton, settings])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        settingsPanel.backgroundColor = UIColor(white: 0.08, alpha: 0.95)
        settingsPanel.isHidden = true
        settingsPanel.layer.cornerRadius = 12
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsPanel)

        settingsLabel.text = "Settings\n\n• Sound: On\n• Controls: Left run / Right look\n• During GOD RED chase: look back — stick still flees\n\n(Tap anywhere to close)"
        settingsLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        settingsLabel.textColor = .white
        settingsLabel.textAlignment = .center
        settingsLabel.numberOfLines = 0
        settingsLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.addSubview(settingsLabel)

        let closeTap = UITapGestureRecognizer(target: self, action: #selector(closeSettings))
        settingsPanel.addGestureRecognizer(closeTap)

        setupSavesPanel()

        NSLayoutConstraint.activate([
            artView.topAnchor.constraint(equalTo: topAnchor),
            artView.leadingAnchor.constraint(equalTo: leadingAnchor),
            artView.trailingAnchor.constraint(equalTo: trailingAnchor),
            artView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.55),

            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: artView.bottomAnchor, constant: 28),
            stack.widthAnchor.constraint(equalToConstant: 220),

            settingsPanel.centerXAnchor.constraint(equalTo: centerXAnchor),
            settingsPanel.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsPanel.widthAnchor.constraint(equalToConstant: 300),
            settingsPanel.heightAnchor.constraint(equalToConstant: 220),
            settingsLabel.centerXAnchor.constraint(equalTo: settingsPanel.centerXAnchor),
            settingsLabel.centerYAnchor.constraint(equalTo: settingsPanel.centerYAnchor),
            settingsLabel.leadingAnchor.constraint(equalTo: settingsPanel.leadingAnchor, constant: 16),
            settingsLabel.trailingAnchor.constraint(equalTo: settingsPanel.trailingAnchor, constant: -16)
        ])

        refreshContinue()
    }

    private func setupSavesPanel() {
        savesPanel.backgroundColor = UIColor(white: 0.06, alpha: 0.97)
        savesPanel.isHidden = true
        savesPanel.layer.cornerRadius = 14
        savesPanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(savesPanel)

        let header = UILabel()
        header.text = "YOUR GAMES"
        header.font = .systemFont(ofSize: 20, weight: .black)
        header.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        header.textAlignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        savesPanel.addSubview(header)

        let subtitle = UILabel()
        subtitle.text = "Pick a game to continue from the same objective"
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = UIColor(white: 0.7, alpha: 1)
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        savesPanel.addSubview(subtitle)

        savesScroll.translatesAutoresizingMaskIntoConstraints = false
        savesPanel.addSubview(savesScroll)

        savesStack.axis = .vertical
        savesStack.spacing = 10
        savesStack.translatesAutoresizingMaskIntoConstraints = false
        savesScroll.addSubview(savesStack)

        let back = makeButton("Back")
        back.addTarget(self, action: #selector(closeSaves), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        savesPanel.addSubview(back)

        NSLayoutConstraint.activate([
            savesPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            savesPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            savesPanel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            savesPanel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),

            header.topAnchor.constraint(equalTo: savesPanel.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: savesPanel.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: savesPanel.trailingAnchor, constant: -12),

            subtitle.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: savesPanel.leadingAnchor, constant: 12),
            subtitle.trailingAnchor.constraint(equalTo: savesPanel.trailingAnchor, constant: -12),

            savesScroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            savesScroll.leadingAnchor.constraint(equalTo: savesPanel.leadingAnchor, constant: 12),
            savesScroll.trailingAnchor.constraint(equalTo: savesPanel.trailingAnchor, constant: -12),
            savesScroll.bottomAnchor.constraint(equalTo: back.topAnchor, constant: -12),

            savesStack.topAnchor.constraint(equalTo: savesScroll.topAnchor),
            savesStack.leadingAnchor.constraint(equalTo: savesScroll.leadingAnchor),
            savesStack.trailingAnchor.constraint(equalTo: savesScroll.trailingAnchor),
            savesStack.bottomAnchor.constraint(equalTo: savesScroll.bottomAnchor),
            savesStack.widthAnchor.constraint(equalTo: savesScroll.widthAnchor),

            back.centerXAnchor.constraint(equalTo: savesPanel.centerXAnchor),
            back.bottomAnchor.constraint(equalTo: savesPanel.bottomAnchor, constant: -16),
            back.widthAnchor.constraint(equalToConstant: 160)
        ])
    }

    private func rebuildSavesList() {
        savesStack.arrangedSubviews.forEach {
            savesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let slots = SaveGameStore.allSlots()
        if slots.isEmpty {
            let empty = UILabel()
            empty.text = "No games yet.\nStart a New Game."
            empty.font = .systemFont(ofSize: 16, weight: .semibold)
            empty.textColor = UIColor(white: 0.65, alpha: 1)
            empty.textAlignment = .center
            empty.numberOfLines = 0
            savesStack.addArrangedSubview(empty)
            return
        }

        for (index, slot) in slots.enumerated() {
            let row = UIButton(type: .system)
            let date = SaveGameStore.formattedDate(slot.updatedAt)
            let status = slot.finished ? "WON" : "CONTINUE"
            row.setTitle("#\(index + 1)  \(slot.label)\n\(date)  ·  \(status)", for: .normal)
            row.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            row.titleLabel?.numberOfLines = 2
            row.titleLabel?.textAlignment = .center
            row.setTitleColor(slot.finished ? UIColor(white: 0.55, alpha: 1) : .white, for: .normal)
            row.backgroundColor = slot.finished
                ? UIColor(white: 0.18, alpha: 1)
                : UIColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 1)
            row.layer.cornerRadius = 10
            row.contentEdgeInsets = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
            row.isEnabled = !slot.finished
            row.alpha = slot.finished ? 0.55 : 1
            row.tag = index
            row.addTarget(self, action: #selector(tapSave(_:)), for: .touchUpInside)
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            savesStack.addArrangedSubview(row)
        }
    }

    private func makeButton(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        style(b)
        return b
    }

    private func style(_ b: UIButton) {
        b.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 1)
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    @objc private func tapNew() { onNewGame?() }

    @objc private func tapContinue() {
        rebuildSavesList()
        savesPanel.isHidden = false
    }

    @objc private func closeSaves() {
        savesPanel.isHidden = true
    }

    @objc private func tapSave(_ sender: UIButton) {
        let slots = SaveGameStore.allSlots()
        guard sender.tag >= 0, sender.tag < slots.count else { return }
        let slot = slots[sender.tag]
        guard !slot.finished else { return }
        onContinueSlot?(slot)
    }

    @objc private func tapSettings() { settingsPanel.isHidden = false }
    @objc private func closeSettings() { settingsPanel.isHidden = true }
}

/// Drawn menu art: dark city, humans, and GOD RED eating one of them.
final class MenuArtView: UIView {
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1).cgColor)
        ctx.fill(rect)

        ctx.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: rect.width * 0.72, y: 36, width: 54, height: 54))

        let houseColors: [UIColor] = [
            UIColor(red: 0.5, green: 0.12, blue: 0.12, alpha: 1),
            UIColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1),
            UIColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1),
            UIColor(red: 0.45, green: 0.35, blue: 0.12, alpha: 1)
        ]
        for i in 0..<6 {
            let x = 20 + CGFloat(i) * (rect.width / 6.2)
            let h = 70 + CGFloat((i * 17) % 40)
            let y = rect.height * 0.42 - h
            ctx.setFillColor(houseColors[i % houseColors.count].cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 48, height: h))
            ctx.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
            ctx.move(to: CGPoint(x: x - 4, y: y))
            ctx.addLine(to: CGPoint(x: x + 24, y: y - 22))
            ctx.addLine(to: CGPoint(x: x + 52, y: y))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 0.85).cgColor)
            ctx.fill(CGRect(x: x + 10, y: y + h * 0.35, width: 10, height: 10))
            ctx.fill(CGRect(x: x + 28, y: y + h * 0.35, width: 10, height: 10))
        }

        ctx.setFillColor(UIColor(white: 0.07, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: rect.height * 0.42, width: rect.width, height: rect.height * 0.58))

        for i in 0..<4 {
            let hx = 40 + CGFloat(i) * 55
            let hy = rect.height * 0.62
            ctx.setFillColor(UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1).cgColor)
            ctx.fill(CGRect(x: hx, y: hy, width: 18, height: 28))
            ctx.setFillColor(UIColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: hx + 2, y: hy - 14, width: 14, height: 14))
        }

        let rx = rect.width * 0.58
        let ry = rect.height * 0.52
        ctx.setFillColor(UIColor(red: 0.75, green: 0.05, blue: 0.05, alpha: 1).cgColor)
        ctx.fill(CGRect(x: rx, y: ry, width: 90, height: 110))
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: rx + 18, y: ry + 18, width: 16, height: 16))
        ctx.fillEllipse(in: CGRect(x: rx + 52, y: ry + 18, width: 16, height: 16))
        ctx.fillEllipse(in: CGRect(x: rx + 18, y: ry + 42, width: 16, height: 16))
        ctx.fillEllipse(in: CGRect(x: rx + 52, y: ry + 42, width: 16, height: 16))
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: rx + 20, y: ry + 70, width: 50, height: 18))
        ctx.setFillColor(UIColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: rx + 34, y: ry + 72, width: 14, height: 14))
        ctx.setFillColor(UIColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    }
}
