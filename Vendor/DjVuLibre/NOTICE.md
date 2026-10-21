# Bundled native dependencies

DjVuLibre 3.5.30 (GPL-2.0-or-later) and libjpeg-turbo 3.2.0 (IJG and BSD-style terms) are copied from the pre-existing local MacPorts installation. No package was installed by this milestone. The copies have modified Mach-O install names and ad-hoc signatures; upstream decoding code is unchanged. MacPorts Portfiles document original build configuration and patches. Original DjVuLibre sources, copyright and GPL text accompany this project. JPEG sources and license documents are included, together with the MacPorts DjVuLibre patch.

The bundled binaries support x86_64 and require macOS 26.0 or later. The Xcode deployment target reflects that requirement. End users do not need MacPorts, Homebrew or command-line utilities. Only project-local dynamic libraries are loaded. Build-time fixture generation used tools already installed in /opt/local; these tools are not runtime dependencies.

Before distributing binaries linked to DjVuLibre, use a GPL-compatible license for the combined application, provide required notices and license texts, and provide complete corresponding source (application, library, modifications and build scripts) using a GPL-compliant distribution method. Merely linking to an upstream repository is not a substitute for meeting source obligations. This development milestone does not choose or change the application's license or authorize a release. Private local use does not publish the project.

Source: https://sourceforge.net/projects/djvu/files/DjVuLibre/3.5.30/
GPL: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
JPEG: https://github.com/libjpeg-turbo/libjpeg-turbo/tree/3.2.0

SHA-256 of vendored DjVuLibre source archive:
`ee5e457d4cfebe566f94b99e5e3d3cc7f5c79ddb741c2ac2ba2e456f00329644`

Build integration: Xcode links Vendor/DjVuLibre/libdjvulibre.dylib and copies the versioned libraries and notices into Contents/Frameworks and Contents/Resources/Licenses. The decoder resolves JPEG through @loader_path. Production signing/notarization must sign embedded libraries with the release identity; development copies are ad-hoc signed.
