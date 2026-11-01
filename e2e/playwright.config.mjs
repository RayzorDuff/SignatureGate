import {defineConfig} from '@playwright/test';
process.umask(0o077);
export default defineConfig({
  testDir:'./specs',workers:1,fullyParallel:false,retries:0,timeout:45000,
  globalSetup:'./setup.mjs',outputDir:'./artifacts/results',
  reporter:[['list'],['html',{outputFolder:'artifacts/report',open:'never'}],['json',{outputFile:'artifacts/results.json'}]],
  use:{baseURL:process.env.E2E_APPSMITH_URL,storageState:'.auth/reviewer.json',
       screenshot:'only-on-failure',trace:'retain-on-failure',video:'off'},
});
