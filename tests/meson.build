# Unit tests for the UI-free service core (see opensprogskole_core in
# src/meson.build); they run under `meson test`.
test_error_details = executable('test-error-details',
  'test-error-details.vala',
  link_with: opensprogskole_core,
  # The generated opensprogskole-core.h lands in the library's build dir.
  include_directories: include_directories('../src'),
  dependencies: opensprogskole_core_deps,
)
test('error-details', test_error_details)
