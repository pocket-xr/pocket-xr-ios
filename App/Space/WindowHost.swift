import PocketXRCore
import UIKit
import WebKit

/// What a window's content must do for the pointer and keyboard. iOS lets no app send real touches to a view, so a
/// web page gets them as DOM events through JavaScript, and Pocket XR's own panels find the control under the point.
@MainActor
protocol SpaceContent: AnyObject {
    var view: UIView { get }
    var title: String { get }
    func click(at p: CGPoint)
    func hover(at p: CGPoint)
    func scroll(at p: CGPoint, dx: CGFloat, dy: CGFloat)
    func type(_ text: String)
    func key(_ name: String)
    func goBack()
    func reload()
}

/// One window: its content on top and a bar of window keys below (Back, Reload, Wide view, Snap, Close).
final class WindowHost: UIView {
    static let barHeight: CGFloat = 56

    let id: UUID
    let content: SpaceContent
    private let bar = UIStackView()
    private let titleLabel = UILabel()
    private let lockBadge = UIImageView(image: UIImage(systemName: "lock.fill"))
    var onAction: ((String) -> Void)?

    var focused = false {
        didSet {
            guard focused != oldValue else { return }
            updateRim()
        }
    }

    var locked = false {
        didSet { lockBadge.isHidden = !locked }
    }

    init(id: UUID, size: CGSize, content: SpaceContent, showsBack: Bool) {
        self.id = id
        self.content = content
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        layer.cornerRadius = 22
        layer.masksToBounds = true
        layer.borderWidth = 3
        layer.allowsEdgeAntialiasing = true
        let cv = content.view
        cv.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height - Self.barHeight)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(cv)

        bar.axis = .horizontal
        bar.spacing = 10
        bar.alignment = .center
        bar.isLayoutMarginsRelativeArrangement = true
        bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        bar.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        bar.frame = CGRect(x: 0, y: size.height - Self.barHeight, width: size.width, height: Self.barHeight)
        bar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        addSubview(bar)
        if showsBack {
            bar.addArrangedSubview(key("chevron.backward", "Back", "back"))
            bar.addArrangedSubview(key("arrow.clockwise", "Reload", "reload"))
            bar.addArrangedSubview(key("rectangle.expand.vertical", "Wide view", "wide"))
        }
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.64)
        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(titleLabel)
        lockBadge.tintColor = UIColor.white.withAlphaComponent(0.64)
        lockBadge.isHidden = true
        bar.addArrangedSubview(lockBadge)
        bar.addArrangedSubview(key("square.split.2x1", "Snap", "snap"))
        bar.addArrangedSubview(key("xmark", "Close", "close"))
        updateRim()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setTitle(_ t: String) { titleLabel.text = t }

    private func key(_ symbol: String, _ label: String, _ action: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.85)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let b = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onAction?(action) })
        b.accessibilityLabel = label
        return b
    }

    private func updateRim() {
        layer.borderColor = focused
            ? UIColor(red: 0.35, green: 0.58, blue: 1, alpha: 0.95).cgColor
            : UIColor.white.withAlphaComponent(0.14).cgColor
    }

    /// Whether a point (in this view's points) is on the bar of window keys.
    func onBar(_ p: CGPoint) -> Bool { p.y >= bounds.height - Self.barHeight }

    /// A click at [p]: a window key on the bar, else the content.
    func click(at p: CGPoint) {
        if onBar(p) {
            let q = convert(p, to: bar)
            if let hit = bar.hitTest(q, with: nil), let c = hit as? UIControl ?? hit.superviewControl {
                if let b = c as? UIButton { b.performPrimaryAction() } else { c.sendActions(for: .touchUpInside) }
            }
            return
        }
        content.click(at: p)
    }
}

extension UIView {
    /// The nearest UIControl this view sits in, for clicks that land on a button's label or image.
    var superviewControl: UIControl? {
        var v: UIView? = superview
        while let x = v {
            if let c = x as? UIControl { return c }
            v = x.superview
        }
        return nil
    }
}

// MARK: - Web windows

/// A web page in a window. Pointer clicks, scrolls and typing arrive as DOM events from a small script (pxrScript).
@MainActor
final class WebContent: NSObject, SpaceContent, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    var view: UIView { web }
    var title: String { web.title?.isEmpty == false ? web.title! : (web.url?.host ?? "Web") }
    var onChange: (() -> Void)?

    init(url: String, desktop: Bool) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Clicks arrive from a script, which a page does not count as a tap, so media may start without one.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = desktop ? .desktop : .recommended
        config.userContentController.addUserScript(WKUserScript(source: Self.pxrScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 744), configuration: config)
        super.init()
        self.desktop = desktop
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        load(url)
    }

    func load(_ url: String) {
        if url == TestPage.url {
            web.loadHTMLString(TestPage.html, baseURL: nil)
        } else if let u = URL(string: url) {
            web.load(URLRequest(url: u))
        }
    }

    var currentURL: String? {
        guard let u = web.url?.absoluteString, !u.isEmpty, u != "about:blank" else { return nil }
        return u
    }

    private(set) var desktop = false

    func setDesktop(_ on: Bool) {
        desktop = on
        web.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = desktop ? .desktop : .recommended
        decisionHandler(.allow, preferences)
    }

    private func js(_ s: String) {
        web.evaluateJavaScript(s, completionHandler: nil)
    }

    func click(at p: CGPoint) { js("window.__pxr && __pxr.click(\(Double(p.x)), \(Double(p.y)))") }
    func hover(at p: CGPoint) { js("window.__pxr && __pxr.hover(\(Double(p.x)), \(Double(p.y)))") }
    func scroll(at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        js("window.__pxr && __pxr.scroll(\(Double(p.x)), \(Double(p.y)), \(Double(dx)), \(Double(dy)))")
    }
    func type(_ text: String) {
        guard let data = try? JSONEncoder().encode(text), let s = String(data: data, encoding: .utf8) else { return }
        js("window.__pxr && __pxr.type(\(s))")
    }
    func key(_ name: String) { js("window.__pxr && __pxr.key('\(name)')") }
    func goBack() { if web.canGoBack { web.goBack() } }
    func reload() { web.reload() }

    // A link that opens a new window opens in this one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onChange?() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { onChange?() }

    /// Pointer and keyboard as DOM events. Clicks: pointer and mouse down and up, focus, then click(). Scrolls: the
    /// nearest scrollable box under the point, else the page. Typing: insertText into the focused field.
    static let pxrScript = """
    window.__pxr = (function () {
      function at(x, y) { return document.elementFromPoint(x, y); }
      function ev(t, type, x, y, P) {
        try {
          var o = { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, view: window,
                    button: 0, buttons: /down$/.test(type) ? 1 : 0, pointerType: 'mouse', isPrimary: true, pointerId: 1 };
          t.dispatchEvent(new P(type, o));
        } catch (e) {}
      }
      function scroller(el) {
        while (el && el !== document.body && el !== document.documentElement) {
          var s = getComputedStyle(el);
          if ((/(auto|scroll)/.test(s.overflowY) && el.scrollHeight > el.clientHeight) ||
              (/(auto|scroll)/.test(s.overflowX) && el.scrollWidth > el.clientWidth)) return el;
          el = el.parentElement;
        }
        return null;
      }
      var lastHover = null;
      return {
        click: function (x, y) {
          var t = at(x, y); if (!t) return 'none';
          ev(t, 'pointerdown', x, y, PointerEvent); ev(t, 'mousedown', x, y, MouseEvent);
          var f = t.closest('input,textarea,select,[contenteditable=""],[contenteditable="true"],button,a') || t;
          try { if (f.focus) f.focus({ preventScroll: true }); } catch (e) {}
          ev(t, 'pointerup', x, y, PointerEvent); ev(t, 'mouseup', x, y, MouseEvent);
          if (t.click) t.click(); else ev(t, 'click', x, y, MouseEvent);
          return t.tagName;
        },
        hover: function (x, y) {
          var t = at(x, y); if (!t) return;
          if (t !== lastHover) {
            if (lastHover) { ev(lastHover, 'pointerout', x, y, PointerEvent); ev(lastHover, 'mouseout', x, y, MouseEvent); }
            ev(t, 'pointerover', x, y, PointerEvent); ev(t, 'mouseover', x, y, MouseEvent);
            lastHover = t;
          }
          ev(t, 'pointermove', x, y, PointerEvent); ev(t, 'mousemove', x, y, MouseEvent);
        },
        scroll: function (x, y, dx, dy) {
          var s = scroller(at(x, y));
          if (s) s.scrollBy(dx, dy); else window.scrollBy(dx, dy);
        },
        type: function (text) {
          var a = document.activeElement;
          if (a && (a.isContentEditable || /^(INPUT|TEXTAREA)$/.test(a.tagName))) {
            if (!document.execCommand('insertText', false, text)) {
              a.value = (a.value || '') + text;
              a.dispatchEvent(new Event('input', { bubbles: true }));
            }
          }
          for (var i = 0; i < text.length; i++) {
            var k = { key: text[i], bubbles: true };
            (a || document.body).dispatchEvent(new KeyboardEvent('keydown', k));
            (a || document.body).dispatchEvent(new KeyboardEvent('keyup', k));
          }
        },
        key: function (name) {
          var a = document.activeElement || document.body;
          var o = { key: name, code: name, bubbles: true, cancelable: true };
          var go = a.dispatchEvent(new KeyboardEvent('keydown', o));
          if (go) {
            if (name === 'Backspace') document.execCommand('delete');
            else if (name === 'Enter') {
              if (a.tagName === 'TEXTAREA' || a.isContentEditable) document.execCommand('insertLineBreak');
              else if (a.form) { if (a.form.requestSubmit) a.form.requestSubmit(); else a.form.submit(); }
            }
            else if (name === 'Tab') {
              var f = Array.prototype.filter.call(document.querySelectorAll('a,button,input,textarea,select,[tabindex]'), function (e) { return e.tabIndex >= 0; });
              var i = f.indexOf(a); if (f.length) f[(i + 1) % f.length].focus();
            }
            else if (name === 'ArrowDown') window.scrollBy(0, 60);
            else if (name === 'ArrowUp') window.scrollBy(0, -60);
            else if (name === 'PageDown' || name === ' ') window.scrollBy(0, innerHeight * 0.85);
            else if (name === 'PageUp') window.scrollBy(0, -innerHeight * 0.85);
            else if (name === 'Escape' && a.blur) a.blur();
          }
          a.dispatchEvent(new KeyboardEvent('keyup', o));
        }
      };
    })();
    """
}

// MARK: - Pocket XR's own panels

/// A panel of Pocket XR's own UIKit controls (the launcher, the Control Center). A click finds the control under
/// the point and sends it its action, as a tap would.
@MainActor
class PanelContent: NSObject, SpaceContent {
    let root = UIView()
    var view: UIView { root }
    var title: String { "" }
    /// The field that typing goes to, if the panel has one.
    var typingTarget: UITextField?

    func click(at p: CGPoint) {
        guard let hit = root.hitTest(p, with: nil) else { return }
        if let field = hit as? UITextField ?? hit.superview as? UITextField {
            typingTarget = field
            return
        }
        guard let c = hit as? UIControl ?? hit.superviewControl, c.isEnabled else { return }
        if let s = c as? UISwitch {
            s.setOn(!s.isOn, animated: true)
            s.sendActions(for: .valueChanged)
        } else if let seg = c as? UISegmentedControl {
            let local = seg.convert(p, from: root)
            let n = seg.numberOfSegments
            if n > 0 {
                seg.selectedSegmentIndex = min(n - 1, max(0, Int(local.x / max(seg.bounds.width, 1) * CGFloat(n))))
                seg.sendActions(for: .valueChanged)
            }
        } else if let b = c as? UIButton {
            b.performPrimaryAction()
        } else {
            c.sendActions(for: .touchUpInside)
        }
    }

    func hover(at p: CGPoint) {}
    func scroll(at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        if let s = root.hitTest(p, with: nil)?.enclosingScrollView {
            var o = s.contentOffset
            o.y = min(max(o.y + dy, -s.adjustedContentInset.top), max(s.contentSize.height - s.bounds.height, 0))
            s.setContentOffset(o, animated: false)
        }
    }

    func type(_ text: String) {
        guard let f = typingTarget else { return }
        f.text = (f.text ?? "") + text
        f.sendActions(for: .editingChanged)
    }

    func key(_ name: String) {
        guard let f = typingTarget else { return }
        switch name {
        case "Backspace":
            if var t = f.text, !t.isEmpty { t.removeLast(); f.text = t; f.sendActions(for: .editingChanged) }
        case "Enter":
            f.sendActions(for: .editingDidEndOnExit)
        case "Escape":
            f.text = ""
            f.sendActions(for: .editingChanged)
        default:
            break
        }
    }

    func goBack() {}
    func reload() {}
}

extension UIView {
    var enclosingScrollView: UIScrollView? {
        var v: UIView? = self
        while let x = v {
            if let s = x as? UIScrollView { return s }
            v = x.superview
        }
        return nil
    }
}

/// A page for testing pointer input without the network (the self-test, and "Test page" in the launcher).
enum TestPage {
    // Plain strings, usable anywhere.
    static let url = "pocketxr:test"
    static let html = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width">
    <style>
      body { background:#0C0D10; color:#fff; font:28px -apple-system, sans-serif; margin:40px; }
      button { font-size:32px; padding:18px 36px; border-radius:16px; border:0; background:#5A93FF; color:#fff; }
      input { font-size:30px; padding:14px; width:520px; border-radius:12px; border:2px solid #444; background:#15171C; color:#fff; }
      #list { height:260px; overflow-y:auto; border:2px solid #333; border-radius:12px; margin-top:24px; }
      #list div { padding:14px 20px; border-bottom:1px solid #222; }
    </style></head><body>
    <h2>Pocket XR test page</h2>
    <button id="btn" onclick="document.getElementById('out').textContent='clicked ' + (++window.clicks)">Click me</button>
    <span id="out" style="margin-left:24px">not clicked</span>
    <p><input id="field" placeholder="Type here"></p>
    <div id="list"></div>
    <script>
      window.clicks = 0;
      var l = document.getElementById('list');
      for (var i = 1; i <= 60; i++) { var d = document.createElement('div'); d.textContent = 'Row ' + i; l.appendChild(d); }
      window.__pxrRect = function (id) { var r = document.getElementById(id).getBoundingClientRect();
        return [r.left + r.width / 2, r.top + r.height / 2]; };
    </script></body></html>
    """
}
