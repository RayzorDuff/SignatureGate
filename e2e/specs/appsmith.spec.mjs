import {test,expect} from '@playwright/test';
import {browserTarget} from '../safety.mjs';
import {selectors,locate,isolate,query} from '../helpers.mjs';
test.beforeEach(async({context})=>{await isolate(context);});
test('authenticated real application loads and backend identity is scoped',async({page})=>{
  const target=browserTarget();const s=await selectors();await page.goto(target.app);
  await expect(locate(page,s.applicationReady)).toBeVisible();
  const rows=await query("SELECT application_member_access('practitioner@example.invalid',$1::uuid,false) allowed, application_member_access('practitioner@example.invalid',$2::uuid,false) forbidden",['27000000-0000-4000-8000-000000000003','27000000-0000-4000-8000-000000000004']);
  expect(rows[0]).toEqual({allowed:true,forbidden:false});
});
test('anonymous cash writes exactly one donation and one audit record',async({page})=>{
  const target=browserTarget();const s=await selectors();await page.goto(target.app);
  await locate(page,s.contributorSelect).click();await locate(page,s.anonymousOption).click();
  await locate(page,s.amount).fill('1.37');await locate(page,s.notes).fill('SignatureGate E2E cash operation');
  await locate(page,s.submitCash).click();await expect(locate(page,s.successFeedback)).toBeVisible();
  await expect.poll(async()=>Number((await query("SELECT count(*)::int n FROM donations WHERE notes='SignatureGate E2E cash operation'"))[0].n)).toBe(1);
  const rows=await query("SELECT d.amount_cents,d.donor_kind,d.status,(SELECT count(*)::int FROM audit_log a WHERE a.entity_id=d.donation_id::text AND a.action='donation.cash.created') audit_count FROM donations d WHERE notes='SignatureGate E2E cash operation'");
  expect(rows).toEqual([{amount_cents:137,donor_kind:'anonymous',status:'pending_review',audit_count:1}]);
  await expect(locate(page,s.errorFeedback)).toHaveCount(0);
});
