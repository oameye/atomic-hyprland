#!/usr/bin/env bash
set -euo pipefail

# Enable a COPR, immediately disable it, then install packages from it via
# --enablerepo so no .repo file survives in the final image.
copr_install_isolated() {
	local copr_name="$1"
	shift
	local packages=("$@")
	local repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"

	dnf5 -y copr enable "$copr_name"
	dnf5 -y copr disable "$copr_name"
	dnf5 -y install --setopt=install_weak_deps=False \
		--enablerepo="$repo_id" "${packages[@]}"
}

# Live COPRs — leave them enabled so rpm-ostree upgrade keeps pulling updates.
# Use dnf5's COPR integration instead of hard-coding the .repo URL layout:
# some COPRs do not publish the legacy fedora-$release filename pattern.
#
# gpu-screen-recorder moved off the old pgo COPR for Fedora 43; this repo
# still publishes the native package name the image layers (`gpu-screen-recorder`).
dnf5 -y copr enable brycensranch/gpu-screen-recorder-git

cat >/etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# Docker CE — added disabled; installed later via --enablerepo.
dnf5 config-manager addrepo \
	--from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i 's/^enabled=.*/enabled=0/g' /etc/yum.repos.d/docker-ce.repo
