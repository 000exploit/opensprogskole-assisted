i18n.gettext('opensprogskole', preset: 'glib')

# The catalogs above are installed with the 'i18n' tag (hardcoded in Meson's
# i18n module), but pixiewood stages the APK with `meson install --tags
# runtime`, which would drop them. Re-install them under the 'runtime' tag; on
# a plain `meson install` this merely overwrites the same files.
meson.add_install_script(
  files('install-runtime-mo.py'),
  meson.project_name(),
  get_option('localedir'),
  install_tag: 'runtime',
)
