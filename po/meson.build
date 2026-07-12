# The xgettext presets fill the .pot header so new catalogs don't start with
# placeholder boilerplate. (The "FIRST AUTHOR"/title comment lines have no
# option — gettext reserves those for each translator to fill.)
i18n.gettext('opensprogskole',
  preset: 'glib',
  args: [
    '--copyright-holder=000exploit',
    '--msgid-bugs-address=https://github.com/000exploit/opensprogskole-assisted/issues',
  ],
)

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
