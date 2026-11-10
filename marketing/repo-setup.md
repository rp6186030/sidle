# Repo and accounts checklist

1. **Buy Me a Coffee**: register the handle used in the code. It is set in one constant, `Links.coffeeHandle` in `Sources/Sidle/Support.swift`, and repeated in `README.md`, `docs/index.html`, `.github/workflows/release.yml` and this folder. If your handle is not `rp6186030`, replace it everywhere:
   ```bash
   grep -rl 'buymeacoffee.com/rp6186030' . --exclude-dir=.build --exclude-dir=dist | xargs sed -i '' 's#buymeacoffee.com/rp6186030#buymeacoffee.com/YOURHANDLE#g'
   ```
2. **GitHub repo** `rp6186030/sidle`, public.
   - Description: `Volume, brightness and media seek on your Mac trackpad edges. Free and open source.`
   - Topics: `macos` `trackpad` `gestures` `menubar` `swift` `productivity` `volume-control` `brightness` `macos-app`
   - Social preview image: `docs/og.png`
   - Add `FUNDING.yml` (already in `.github/`) so the Sponsor button shows your coffee link.
3. **Release**: `git tag v1.0.0 && git push origin main --tags`. The workflow attaches `Sidle-1.0.0.zip`.
4. **GitHub Pages**: Settings → Pages → deploy from branch `main`, folder `/docs`. The landing page is then live at `https://rp6186030.github.io/sidle/`.
5. **Homebrew tap**: create repo `rp6186030/homebrew-sidle`, add `packaging/homebrew/sidle.rb` as `Casks/sidle.rb`.
6. **Directories** (after launch day): AlternativeTo (alternative to MacEdge, Slidr, BetterTouchTool), MacUpdate, and pull requests to `jaywcjlove/awesome-mac` and `serhii-londar/open-source-mac-os-apps`.
