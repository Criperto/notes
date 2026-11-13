%define _unpackaged_files_terminate_build 0
%define debug_package %{nil}

Name:           criperto-notes
Version:        0.2.8
Release:        1%{?dist}
Summary:        Editor moderno y nativo de notas en Markdown para Wayland
License:        GPL-3.0-or-later
URL:            https://github.com/Criperto/notes

AutoReqProv:    no
Requires:       qt6-qtbase, qt6-qtdeclarative, qt6-qtsvg

%description
Aplicación nativa de notas en Markdown con editor de bloques y diagramas Mermaid
para Wayland.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
PREFIX=/usr DESTDIR=%{buildroot} bash %{_sourcedir}/scripts/install.sh --system

%files
/usr/bin/criperto-notes
/usr/share/applications/dev.criperto.Notas.desktop
/usr/share/icons/hicolor/scalable/apps/dev.criperto.Notas.svg
/usr/share/metainfo/dev.criperto.Notas.metainfo.xml
/usr/share/criperto-notes
