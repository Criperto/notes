Name:           notas
Version:        0.1.10
Release:        1%{?dist}
Summary:        Editor moderno y nativo de notas en Markdown para Wayland
License:        GPL-3.0-or-later
URL:            https://github.com/Criperto/notes

AutoReqProv:    yes
Requires:       qt6-qtbase qt6-qtdeclarative qt6-qtsvg hunspell

%description
Aplicación nativa de notas en Markdown con editor de bloques y diagramas Mermaid
para Wayland.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
PREFIX=/usr DESTDIR=%{buildroot} bash %{_sourcedir}/scripts/install-system.sh

%files
/usr/bin/notas
/usr/share/applications/dev.criperto.Notas.desktop
/usr/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg
/usr/share/metainfo/dev.criperto.Notas.metainfo.xml
/usr/share/notas
