// RETIRED after the installed server rejected the request with HTTP 400.
// Kept at the old download path so a fresh copy cannot repeat configuration writes.
// Use DIRECTORY_STARTUP_REBUILD.md for the native editor sequence instead.
// This compatibility notice performs no requests and changes no browser/app state.
(function retiredDirectoryStartupRepair() {
  const report={operation:'signaturegate_directory_startup_rebuild',status:'retired',reason:'use_native_editor_settings',configuration_requests:0};
  console.log(JSON.stringify(report,null,2));
  return report;
})()
