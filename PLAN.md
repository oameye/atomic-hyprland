# Atomic-Hyprland Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal Fedora Atomic image shipping Hyprland on top of `ghcr.io/ublue-os/base-main:43`, with HyDE as the post-rebase rice.

**Architecture:** Raw `Containerfile` + `build.sh` on `base-main`. Static system files live under `files/`. Image built and pushed to GHCR by a single GitHub Actions workflow. No cosign, no ISO, no BlueBuild.

**Tech Stack:** `podman`, `dnf5`, `rpm-ostree`, systemd, `flatpak`, GitHub Actions, Universal Blue `base-main`, HyDE (`HyDE-Project/HyDE` + `HyDE-Project/sddm-hyprland`), Hyprland (via `solopasha/hyprland` COPR).

## Test strategy

Unlike a typical software project, "tests" here are:

- **Build tests:** `podman build .` succeeds locally.
- **Boot tests:** run the built image in a VM via `bootc-image-builder` *or* rebase a throwaway Fedora Atomic install to the image tag.
- **Smoke tests:** after first boot, verify SDDM greeter renders, Hyprland session launches, `ujust update` exits 0, Zen browser installed by the oneshot.

Verification steps in each task show the exact command and the expected output. There is no unit-test suite.

---

### Task 1: Initialize repo skeleton

**Files:**
- Create: `.gitignore`
- Create: `README.md` (stub)
- Create: `files/.gitkeep`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Local build artifacts
*.tar
*.iso
*.tar.gz
output/
tmp/

# Editor droppings
.idea/
.vscode/
*.swp
*~
.DS_Store
```

- [ ] **Step 2: Write `README.md` stub**

```markdown
# atomic-hyprland

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland + HyDE.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Rebase

```sh
rpm-ostree rebase ostree-unverified-registry:ghcr.io/<gh-user>/atomic-hyprland:43
systemctl reboot
```

## After first boot

Run HyDE's installer once:

```sh
bash <(curl -s https://raw.githubusercontent.com/HyDE-Project/HyDE/master/Scripts/install.sh)
```

For ghostty theming, also clone [`HyDE-Project/terminal-emulators`](https://github.com/HyDE-Project/terminal-emulators) and copy its `ghostty/` directory into `~/.config/`.

## Rollback

```sh
rpm-ostree rollback && systemctl reboot
```
```

Replace `<gh-user>` with your GitHub username before publishing.

- [ ] **Step 3: Create empty `files/` dir**

```bash
mkdir -p files && touch files/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore README.md files/.gitkeep
git commit -m "chore: initial repo skeleton"
```

---

### Task 2: Ship `atomic-hyprland-dx-groups` service + script

**Files:**
- Create: `files/usr/bin/atomic-hyprland-dx-groups`
- Create: `files/usr/lib/systemd/system/atomic-hyprland-dx-groups.service`

Purpose: on first boot, create the `docker`/`incus-admin`/`libvirt` groups in `/etc/group` (lifted from `/usr/lib/group`) and add all wheel members to them. Verbatim port of [`ublue-os/bluefin` `bluefin-dx-groups`](https://github.com/ublue-os/bluefin/tree/main/system_files/dx/usr).

- [ ] **Step 1: Write the script**

```bash
mkdir -p files/usr/bin files/usr/lib/systemd/system
```

Write `files/usr/bin/atomic-hyprland-dx-groups`:

```bash
#!/usr/bin/env bash

# Ported verbatim from ublue-os/bluefin bluefin-dx-groups with a rename.
# See DESIGN.md → "Upstream fidelity" table.

GROUP_SETUP_VER=1
GROUP_SETUP_VER_FILE="/etc/ublue/dx-groups"
GROUP_SETUP_VER_RAN=$(cat "$GROUP_SETUP_VER_FILE" 2>/dev/null || echo "")

mkdir -p /etc/ublue

if [[ -f $GROUP_SETUP_VER_FILE && "$GROUP_SETUP_VER" = "$GROUP_SETUP_VER_RAN" ]]; then
  echo "Group setup has already run. Exiting..."
  exit 0
fi

append_group() {
  local group_name="$1"
  if ! grep -q "^$group_name:" /etc/group; then
    echo "Appending $group_name to /etc/group"
    grep "^$group_name:" /usr/lib/group | tee -a /etc/group >/dev/null
  fi
}

append_group docker
append_group incus-admin
append_group libvirt

wheelarray=($(getent group wheel | cut -d ":" -f 4 | tr ',' '\n'))
for user in $wheelarray; do
  usermod -aG docker "$user"
  usermod -aG incus-admin "$user"
  usermod -aG libvirt "$user"
done

echo "$GROUP_SETUP_VER" >"$GROUP_SETUP_VER_FILE"
```

- [ ] **Step 2: Make the script executable in git**

```bash
chmod +x files/usr/bin/atomic-hyprland-dx-groups
```

- [ ] **Step 3: Write the systemd unit**

Write `files/usr/lib/systemd/system/atomic-hyprland-dx-groups.service`:

```ini
[Unit]
Description=Add wheel members to docker/incus-admin/libvirt groups
After=systemd-user-sessions.service

[Service]
Type=oneshot
ExecStart=/usr/bin/atomic-hyprland-dx-groups
Restart=on-failure
RestartSec=30
StartLimitInterval=0

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Commit**

```bash
git add files/usr/bin/atomic-hyprland-dx-groups \
        files/usr/lib/systemd/system/atomic-hyprland-dx-groups.service
git commit -m "feat: port bluefin-dx-groups oneshot for wheel→docker/libvirt"
```

---

### Task 3: Ship SDDM configuration files

**Files:**
- Create: `files/etc/sddm.conf.d/the_hyde_project.conf`
- Create: `files/etc/sddm.conf.d/backup_the_hyde_project.conf`

- [ ] **Step 1: Create the config dir**

```bash
mkdir -p files/etc/sddm.conf.d
```

- [ ] **Step 2: Write `the_hyde_project.conf` (selects the Corners theme pre-baked at build time)**

```ini
[Theme]
Current=Corners
```

Write that content to `files/etc/sddm.conf.d/the_hyde_project.conf`.

- [ ] **Step 3: Write empty marker file**

```bash
: > files/etc/sddm.conf.d/backup_the_hyde_project.conf
```

This file's presence is checked by HyDE's `install_pst.sh` to skip SDDM reconfiguration at user install time.

- [ ] **Step 4: Commit**

```bash
git add files/etc/sddm.conf.d/
git commit -m "feat: ship SDDM conf selecting HyDE Corners + skip-marker"
```

---

### Task 4: Ship Zen Browser first-boot install unit

**Files:**
- Create: `files/etc/systemd/system/install-zen-browser.service`

- [ ] **Step 1: Create dir and write unit**

```bash
mkdir -p files/etc/systemd/system
```

Write `files/etc/systemd/system/install-zen-browser.service`:

```ini
[Unit]
Description=Install Zen Browser via Flatpak (first boot)
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/atomic-hyprland/zen-installed

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c 'flatpak install -y --noninteractive flathub app.zen_browser.zen && mkdir -p /var/lib/atomic-hyprland && touch /var/lib/atomic-hyprland/zen-installed'

[Install]
WantedBy=multi-user.target
```

Notes:
- Flathub is pre-added system-wide in `build.sh` (Task 7).
- `ConditionPathExists=!` and the post-install `touch` together form the run-once guard.

- [ ] **Step 2: Commit**

```bash
git add files/etc/systemd/system/install-zen-browser.service
git commit -m "feat: first-boot oneshot to install Zen Browser from Flathub"
```

---

### Task 5: Write the Containerfile

**Files:**
- Create: `Containerfile`

- [ ] **Step 1: Write the Containerfile**

```dockerfile
ARG FEDORA_VERSION=43
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

COPY files/ /
COPY build.sh /tmp/build.sh

RUN chmod +x /tmp/build.sh \
 && /tmp/build.sh \
 && ostree container commit
```

Key points:
- `FEDORA_VERSION` is a build-arg so CI can bump it by PR.
- `COPY files/ /` lays down static config/scripts before `build.sh` runs — this way the dx-groups script is in place when `systemctl enable` references its unit.
- `ostree container commit` is the final step per the ostree-container convention.

- [ ] **Step 2: Commit**

```bash
git add Containerfile
git commit -m "feat: Containerfile scaffold on base-main:43"
```

---

### Task 6: Write `build.sh` — repo enablement

**Files:**
- Create: `build.sh`

- [ ] **Step 1: Write the shebang, strict mode, and repo-enable block**

Write `build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

RELEASE="$(rpm -E %fedora)"
echo "Fedora version: ${RELEASE}"

# Pinned upstream tags (SDDM greeter assets only — see DESIGN.md → "Pinned upstream tags").
HYDE_TAG="v26.03.30"
SDDM_HYPRLAND_TAG="v0.48.0"

############################################
# 1. Enable COPR repos
############################################
for i in solopasha/hyprland pgdev/ghostty bigon/nerd-fonts; do
    owner="${i%%/*}"
    repo="${i##*/}"
    curl -fsSL \
        "https://copr.fedorainfracloud.org/coprs/${owner}/${repo}/repo/fedora-${RELEASE}/${owner}-${repo}-fedora-${RELEASE}.repo" \
        -o "/etc/yum.repos.d/_copr_${owner}-${repo}.repo"
done

############################################
# 2. VS Code repo
############################################
cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

############################################
# 3. Docker CE repo — added but disabled by default (uBlue pattern)
############################################
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i 's/^enabled=.*/enabled=0/g' /etc/yum.repos.d/docker-ce.repo

echo "Repos enabled."
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x build.sh
git add build.sh
git commit -m "feat(build): enable COPR + VS Code + Docker repos"
```

---

### Task 7: `build.sh` — install packages

**Files:**
- Modify: `build.sh` (append)

- [ ] **Step 1: Append the package install section**

Append to `build.sh`:

```bash
############################################
# 4. Install the full package set
#    --setopt=install_weak_deps=False for image-size reduction.
############################################
PACKAGES=(
    # Hyprland ecosystem (solopasha COPR)
    hyprland hyprlock hypridle hyprpaper hyprshot hyprpicker hyprcursor
    hyprpolkitagent hyprsunset hyprland-qtutils xdg-desktop-portal-hyprland

    # Session / greeter
    sddm qt6-qtsvg qt6-qtmultimedia qt6-qtdeclarative
    qt5-qtwayland qt5-qtquickcontrols qt5-qtquickcontrols2 qt5-qtgraphicaleffects
    layer-shell-qt5

    # Desktop apps
    ghostty waybar rofi-wayland swaync
    nautilus nautilus-python yazi
    wl-clipboard cliphist
    grim slurp satty
    network-manager-applet blueman bluez-tools
    pavucontrol playerctl pamixer
    xdg-desktop-portal-gtk polkit
    brightnessctl wlr-randr uwsm
    gvfs gvfs-mtp gvfs-smb

    # Developer tooling
    code
    make
    gcc-c++ libstdc++-devel python3-pip sqlite-devel
    eduvpn-client

    # Container stack (Fedora-side)
    podman-compose podman-tui podman-machine flatpak-builder

    # GPU compute (AMD ROCm)
    rocm-hip rocm-opencl rocm-smi

    # Fonts and theming
    fontawesome-fonts-all google-noto-emoji-fonts liberation-fonts
    jetbrains-mono-fonts jetbrains-mono-nerd-fonts
    adwaita-icon-theme papirus-icon-theme bibata-cursor-themes
    kvantum
)

dnf5 -y install --setopt=install_weak_deps=False "${PACKAGES[@]}"

# Docker CE — from the disabled docker-ce-stable repo (uBlue pattern)
dnf5 -y install --setopt=install_weak_deps=False --enablerepo=docker-ce-stable \
    docker-ce docker-ce-cli docker-compose-plugin docker-buildx-plugin containerd.io

echo "Packages installed."
```

- [ ] **Step 2: Commit**

```bash
git add build.sh
git commit -m "feat(build): install package set + Docker CE"
```

---

### Task 8: `build.sh` — override-remove Firefox, SDDM pre-bake

**Files:**
- Modify: `build.sh` (append)

- [ ] **Step 1: Append override-remove block**

Append:

```bash
############################################
# 5. Remove Firefox — user installs Zen Browser Flatpak instead
############################################
rpm-ostree override remove firefox firefox-langpacks || true
# `|| true` — base-main may not ship Firefox in all variants; tolerate absence.
```

- [ ] **Step 2: Append SDDM pre-bake block**

Append:

```bash
############################################
# 6. SDDM greeter pre-bake (see DESIGN.md → "SDDM greeter — pre-baked")
############################################
WORK=$(mktemp -d)
git clone --depth 1 --branch "${SDDM_HYPRLAND_TAG}" \
    https://github.com/HyDE-Project/sddm-hyprland.git "${WORK}/sddm-hyprland"
make -C "${WORK}/sddm-hyprland" install PREFIX=/usr

git clone --depth 1 --branch "${HYDE_TAG}" \
    https://github.com/HyDE-Project/HyDE.git "${WORK}/HyDE"
mkdir -p /usr/share/sddm/themes/Corners
tar -xzf "${WORK}/HyDE/Source/arcs/Sddm_Corners.tar.gz" \
    -C /usr/share/sddm/themes/ --strip-components=0

rm -rf "${WORK}"
```

Note: the tarball already contains a top-level `Corners/` directory, so extracting into `/usr/share/sddm/themes/` lands it at `/usr/share/sddm/themes/Corners/`.

- [ ] **Step 3: Commit**

```bash
git add build.sh
git commit -m "feat(build): remove Firefox and pre-bake SDDM greeter"
```

---

### Task 9: `build.sh` — Flathub, timers, service enables, cleanup

**Files:**
- Modify: `build.sh` (append)

- [ ] **Step 1: Append**

Append:

```bash
############################################
# 7. Flathub remote system-wide
############################################
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

############################################
# 8. Enable systemd units at build time
############################################
systemctl enable sddm.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable flatpak-system-update.timer
systemctl enable podman-auto-update.timer
systemctl --global enable flatpak-user-update.timer
systemctl --global enable podman-auto-update.timer
systemctl enable atomic-hyprland-dx-groups.service
systemctl enable install-zen-browser.service

############################################
# 9. Cleanup dnf caches (image-size hygiene)
############################################
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/libdnf5 /tmp/* /var/tmp/*

echo "Build complete."
```

Note: we keep the COPR `.repo` files in place so `rpm-ostree upgrade` can pick up live updates (see DESIGN.md, build.sh step 11 rationale).

- [ ] **Step 2: Commit**

```bash
git add build.sh
git commit -m "feat(build): Flathub + systemd timers + enables + cleanup"
```

---

### Task 10: Verify `build.sh` script locally (syntax only)

Syntax + shellcheck only — we are not running the build here.

- [ ] **Step 1: Bash syntax check**

```bash
bash -n build.sh
```

Expected: no output, exit 0.

- [ ] **Step 2: shellcheck (if installed)**

```bash
command -v shellcheck && shellcheck build.sh || echo "shellcheck not installed — skip"
```

Expected: no errors, or "not installed — skip". If warnings, fix them inline (most likely: quote all `"${VAR}"` references).

- [ ] **Step 3: No commit if no changes.**

---

### Task 11: Local image build test

**Files:**
- None (builds from current tree)

- [ ] **Step 1: Build the image with podman**

```bash
podman build --pull --build-arg FEDORA_VERSION=43 \
    -t localhost/atomic-hyprland:43-test .
```

Expected: build succeeds, image tagged. Expect build time ~10–20 min on first run (Hyprland stack + Docker CE + ROCm is large).

- [ ] **Step 2: Inspect the resulting image**

```bash
podman inspect localhost/atomic-hyprland:43-test \
    --format '{{.Size}} bytes, {{.RootFS.Type}}, layers={{len .RootFS.Layers}}'
```

Expected: reasonable size (rough range 6–10 GB), ostree-like RootFS.

- [ ] **Step 3: Spot-check that expected files exist in the image**

```bash
podman run --rm localhost/atomic-hyprland:43-test bash -c '
  set -e
  for f in \
    /usr/bin/hyprland \
    /usr/bin/sddm \
    /usr/bin/ghostty \
    /usr/bin/code \
    /usr/bin/docker \
    /usr/bin/atomic-hyprland-dx-groups \
    /usr/share/sddm/themes/Corners/Main.qml \
    /usr/share/hypr/sddm/hyprland.conf \
    /etc/sddm.conf.d/the_hyde_project.conf \
    /etc/sddm.conf.d/backup_the_hyde_project.conf \
    /etc/sddm.conf.d/sddm-hyprland.conf \
    /etc/systemd/system/multi-user.target.wants/install-zen-browser.service; do
    test -e "$f" && echo "OK  $f" || { echo "MISSING $f"; exit 1; }
  done
'
```

Expected: all lines print `OK ...`; no `MISSING` lines; exit 0.

If `MISSING` appears, fix the relevant earlier task and rebuild.

- [ ] **Step 4: If all checks pass, tag a commit**

```bash
git tag -a build-smoke-$(date +%Y%m%d) -m "local build smoke test passed"
```

No file commits; this just marks the point we know the image builds.

---

### Task 12: Write GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Create workflow dir**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write `build.yml`**

```yaml
name: build

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
  schedule:
    - cron: "0 4 * * 1"  # Weekly Mondays 04:00 UTC

env:
  IMAGE_NAME: atomic-hyprland
  IMAGE_REGISTRY: ghcr.io/${{ github.repository_owner }}
  FEDORA_VERSION: "43"

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Free disk space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: true
          android: true
          dotnet: true
          haskell: true
          large-packages: false
          docker-images: false
          swap-storage: false

      - name: Compute tags
        id: tags
        run: |
          DATE=$(date +%Y%m%d)
          SHA=$(git rev-parse --short HEAD)
          if [[ "${{ github.event_name }}" == "pull_request" ]]; then
            TAGS="pr-${{ github.event.pull_request.number }}"
          else
            TAGS="${FEDORA_VERSION} latest ${FEDORA_VERSION}-${DATE} ${SHA}"
          fi
          echo "tags=${TAGS}" >> "$GITHUB_OUTPUT"

      - name: Build image
        id: build
        uses: redhat-actions/buildah-build@v2
        with:
          image: ${{ env.IMAGE_NAME }}
          tags: ${{ steps.tags.outputs.tags }}
          containerfiles: ./Containerfile
          build-args: FEDORA_VERSION=${{ env.FEDORA_VERSION }}
          oci: true

      - name: Log in to GHCR
        if: github.event_name != 'pull_request'
        uses: redhat-actions/podman-login@v1
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push to GHCR
        if: github.event_name != 'pull_request'
        uses: redhat-actions/push-to-registry@v2
        with:
          image: ${{ steps.build.outputs.image }}
          tags: ${{ steps.build.outputs.tags }}
          registry: ${{ env.IMAGE_REGISTRY }}
```

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/build.yml
git commit -m "ci: GitHub Actions workflow for GHCR build + push"
```

---

### Task 13: Push to GitHub and flip GHCR visibility

Manual steps — no file changes.

- [ ] **Step 1: Create the GitHub repo (public) and push**

If repo is not yet on GitHub:

```bash
gh repo create atomic-hyprland --public --source=. --remote=origin --push
```

Otherwise:

```bash
git push -u origin main
```

- [ ] **Step 2: Wait for first CI run to complete**

```bash
gh run watch
```

Expected: single `build` job, ~15–25 min, finishes green. If red, read logs, fix, commit, push.

- [ ] **Step 3: Flip GHCR package visibility to Public**

First CI run pushes `ghcr.io/<you>/atomic-hyprland:43`. The package defaults to private.

1. Open https://github.com/`<you>`?tab=packages
2. Click `atomic-hyprland`
3. Right sidebar → *Package settings*
4. Scroll to *Danger Zone* → *Change visibility* → **Public** → confirm

Verify anonymous pull works:

```bash
podman pull ghcr.io/<you>/atomic-hyprland:43
```

Expected: pull succeeds without login.

- [ ] **Step 4: No commit — this is registry config.**

---

### Task 14: Rebase an existing Fedora Atomic system (or VM) to the image

End-to-end verification on a real system. If you have a spare machine, use it. Otherwise spin up a Fedora Atomic VM.

- [ ] **Step 1: From an existing Fedora Atomic / Aurora install, rebase**

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/<you>/atomic-hyprland:43
systemctl reboot
```

- [ ] **Step 2: At the login screen**

Expected: SDDM greeter appears, styled by HyDE's `Corners` theme, with a power panel and login panel rendered via Hyprland-as-compositor.

- [ ] **Step 3: Log in and verify Hyprland session starts**

After selecting the `Hyprland` session and logging in, expected: a black screen / minimal Hyprland with no rice yet (HyDE userspace not yet installed).

- [ ] **Step 4: Confirm Zen Browser was installed by the oneshot**

```bash
flatpak list | grep -i zen
```

Expected: `Zen Browser   app.zen_browser.zen  <version>  stable  system`.

- [ ] **Step 5: Confirm `ujust update` works**

```bash
ujust update
```

Expected: pulls latest `:43` manifest (no-op if already current), updates flatpaks, runs brew update. Exits 0.

- [ ] **Step 6: Run HyDE's installer**

```bash
bash <(curl -s https://raw.githubusercontent.com/HyDE-Project/HyDE/master/Scripts/install.sh)
```

Expected: installer runs, skips SDDM reconfiguration (because `/etc/sddm.conf.d/backup_the_hyde_project.conf` exists), writes HyDE configs into `~/.config/`.

- [ ] **Step 7: Log out, back in — full HyDE rice should render**

Expected: waybar, wallpaper, keybinds (`Super+/` for cheatsheet) all working.

- [ ] **Step 8: Copy ghostty theming from sidecar**

```bash
git clone --depth 1 https://github.com/HyDE-Project/terminal-emulators ~/terminal-emulators
cp -r ~/terminal-emulators/ghostty ~/.config/
```

Expected: ghostty picks up HyDE theme on next theme switch.

- [ ] **Step 9: If everything works, no commit. Image is live.**

If something fails, diagnose, fix in the repo, merge, wait for CI, `rpm-ostree upgrade`, reboot, re-test.

---

### Task 15: Finalize README with the actual GHCR path

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace `<gh-user>` placeholder with your real username in `README.md`.**

```bash
sed -i "s|<gh-user>|$(gh api user --jq .login)|g" README.md
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): fill in actual GHCR path"
git push
```

---

## Self-review results (inline — done)

**Spec coverage:** every DESIGN.md section maps to a task:
- Architecture/Containerfile → Task 5
- Package layering → Tasks 6, 7
- Container stack parity → Task 7 (packages) + Task 8 (disable-enablerepo pattern for Docker handled in Task 7)
- SDDM pre-bake → Task 8
- Zen Browser first-boot → Task 4 + Task 9 (enable)
- dx-groups oneshot → Task 2 + Task 9 (enable)
- Flathub + update timers → Task 9
- Pinned tags → Task 6 (`HYDE_TAG`, `SDDM_HYPRLAND_TAG`)
- CI + tag strategy → Task 12
- GHCR public visibility → Task 13
- Rebase flow → Task 14
- README → Tasks 1, 15

**Type / identifier consistency:** `HYDE_TAG` and `SDDM_HYPRLAND_TAG` used in Tasks 6 and 8 with the same values and names. `atomic-hyprland-dx-groups` identical across Task 2, Task 9, Task 11.

**Placeholders:** `<gh-user>` is explicit and substituted in Task 15 via `gh api user`. No `TBD` or `TODO`.

**Gap fix:** Task 14 explicitly tests the end-to-end flow on a real system; Task 11 tests the image-build locally; Task 12 covers CI. No scope missed.
