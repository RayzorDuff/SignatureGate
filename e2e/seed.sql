-- Artificial identities only. Fixed UUIDs support repeatable browser/DB assertions.
INSERT INTO people(person_id,display_name) VALUES
 ('27000000-0000-4000-8000-000000000001','Synthetic reviewer'),
 ('27000000-0000-4000-8000-000000000002','Synthetic practitioner'),
 ('27000000-0000-4000-8000-000000000003','Synthetic assigned participant'),
 ('27000000-0000-4000-8000-000000000004','Synthetic unrelated participant');
INSERT INTO person_app_accounts(person_id,email) VALUES
 ('27000000-0000-4000-8000-000000000001','reviewer@example.invalid'),
 ('27000000-0000-4000-8000-000000000002','practitioner@example.invalid');
INSERT INTO person_roles(person_id,role_key,assigned_by) VALUES
 ('27000000-0000-4000-8000-000000000001','document_reviewer','synthetic_e2e'),
 ('27000000-0000-4000-8000-000000000001','donations_reviewer','synthetic_e2e'),
 ('27000000-0000-4000-8000-000000000002','practitioner','synthetic_e2e');
INSERT INTO members(member_id,person_id,status) VALUES
 ('27000000-0000-4000-8000-000000000003','27000000-0000-4000-8000-000000000003','active'),
 ('27000000-0000-4000-8000-000000000004','27000000-0000-4000-8000-000000000004','active');
INSERT INTO member_practitioner_assignments(member_id,practitioner_person_id,status) VALUES
 ('27000000-0000-4000-8000-000000000003','27000000-0000-4000-8000-000000000002','active');
INSERT INTO practitioner_storage_location_access(practitioner_person_id,storage_location_name,status) VALUES
 ('27000000-0000-4000-8000-000000000002','Synthetic assigned location','active');
