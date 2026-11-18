//
//  CutscenePlayer.swift
//  lego-morts-one-3d
 //
//  Simple fullscreen story cutscenes (text + timed advances).
//

import UIKit

final class CutscenePlayer {

    struct Beat {
        let title: String
        let body: String
        let duration: TimeInterval
        let background: UIColor
    }

    private weak var host: UIView?
    private var overlay: UIView?
    private var titleLabel: UILabel?
    private var bodyLabel: UILabel?
    private var beats: [Beat] = []
    private var index = 0
    private var onDone: (() -> Void)?

    func play(on host: UIView, beats: [Beat], completion: @escaping () -> Void) {
        self.host = host
        self.beats = beats
        self.index = 0
        self.onDone = completion

        let overlay = UIView(frame: host.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .black
        overlay.isUserInteractionEnabled = true

        let title = UILabel()
        title.font = .systemFont(ofSize: 28, weight: .black)
        title.textColor = UIColor(red: 1, green: 0.25, blue: 0.25, alpha: 1)
        title.textAlignment = .center
        title.numberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.font = .systemFont(ofSize: 18, weight: .semibold)
        body.textColor = .white
        body.textAlignment = .center
        body.numberOfLines = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        let tip = UILabel()
        tip.text = "Tap to continue"
        tip.font = .systemFont(ofSize: 13, weight: .medium)
        tip.textColor = UIColor(white: 0.65, alpha: 1)
        tip.textAlignment = .center
        tip.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(title)
        overlay.addSubview(body)
        overlay.addSubview(tip)
        host.addSubview(overlay)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -60),
            title.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            body.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 28),
            body.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -28),
            tip.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            tip.centerXAnchor.constraint(equalTo: overlay.centerXAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(advance))
        overlay.addGestureRecognizer(tap)

        self.overlay = overlay
        self.titleLabel = title
        self.bodyLabel = body
        showCurrent()
    }

    @objc private func advance() {
        index += 1
        if index >= beats.count {
            finish()
        } else {
            showCurrent()
        }
    }

    private func showCurrent() {
        guard index < beats.count else { return }
        let beat = beats[index]
        overlay?.backgroundColor = beat.background
        titleLabel?.text = beat.title
        bodyLabel?.text = beat.body
        titleLabel?.alpha = 0
        bodyLabel?.alpha = 0
        UIView.animate(withDuration: 0.35) {
            self.titleLabel?.alpha = 1
            self.bodyLabel?.alpha = 1
        }
        // Auto-advance after duration if the player doesn't tap.
        let captured = index
        DispatchQueue.main.asyncAfter(deadline: .now() + beat.duration) { [weak self] in
            guard let self, self.index == captured else { return }
            self.advance()
        }
    }

    private func finish() {
        overlay?.removeFromSuperview()
        overlay = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
