--
-- PostgreSQL database dump
--

\restrict AaemyxLdH6D532qegYS9nNGYrwtDFJ42sIdnh1jweTVvOl9ZHuHvssVdTI6KFh8

-- Dumped from database version 16.11 (Debian 16.11-1.pgdg13+1)
-- Dumped by pg_dump version 16.11 (Debian 16.11-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: signaturegate
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO signaturegate;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agreement_templates; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.agreement_templates (
    agreement_template_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    version text NOT NULL,
    required_for text[] NOT NULL,
    doc_url text,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.agreement_templates OWNER TO signaturegate;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.audit_log (
    audit_log_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    actor text,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    details jsonb
);


ALTER TABLE public.audit_log OWNER TO signaturegate;

--
-- Name: donations; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.donations (
    donation_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid,
    provider text NOT NULL,
    provider_reference text,
    amount_cents integer,
    currency text DEFAULT 'USD'::text,
    donated_at timestamp with time zone,
    notes text
);


ALTER TABLE public.donations OWNER TO signaturegate;

--
-- Name: events; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.events (
    event_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    name text,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    location text,
    notes text
);


ALTER TABLE public.events OWNER TO signaturegate;

--
-- Name: member_agreements; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.member_agreements (
    member_agreement_id uuid DEFAULT public.uuid_generate_v4(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    agreement_template_id uuid,
    signed_at timestamp with time zone,
    signature_method text NOT NULL,
    evidence_url text,
    verified_by text,
    verified_at timestamp with time zone,
    status text DEFAULT 'pending'::text NOT NULL,
    facilitator_id uuid,
    member_signed_at timestamp with time zone,
    facilitator_signed_at timestamp with time zone,
    opensign_document_id text,
    evidence text,
    member_id uuid NOT NULL
);


ALTER TABLE public.member_agreements OWNER TO signaturegate;

--
-- Name: members; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.members (
    member_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    first_name text,
    last_name text,
    email text,
    phone text,
    date_of_birth date,
    notes text,
    is_facilitator boolean DEFAULT false NOT NULL,
    is_document_reviewer boolean DEFAULT false NOT NULL
);


ALTER TABLE public.members OWNER TO signaturegate;

--
-- Name: sacrament_releases; Type: TABLE; Schema: public; Owner: signaturegate
--

CREATE TABLE public.sacrament_releases (
    sacrament_release_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    released_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    event_id uuid,
    mushroomprocess_product_id text NOT NULL,
    item_name text,
    quantity numeric(12,3) DEFAULT 0 NOT NULL,
    unit text DEFAULT 'g'::text NOT NULL,
    released_by text,
    notes text,
    facilitator_id uuid,
    net_weight_g integer,
    strain text,
    release_type text DEFAULT 'sacrament_release'::text NOT NULL,
    member_agreement_id uuid,
    storage_location_name text,
    status text DEFAULT 'issued'::text NOT NULL,
    voided_at timestamp with time zone,
    voided_by uuid,
    void_reason text
);

ALTER TABLE public.sacrament_releases OWNER TO signaturegate;

--
-- Data for Name: agreement_templates; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.agreement_templates (agreement_template_id, created_at, name, version, required_for, doc_url, active) FROM stdin;
fe1f6fcd-6e64-4df0-a49b-0619b83e2735	2025-12-31 00:13:43.575359+00	Member Acknowledgment & Liability Release	2025-12-01	{membership,sacrament_release}	OPENSIGN_TEMPLATE_OR_PDF_URL	t
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.audit_log (audit_log_id, created_at, actor, action, entity_type, entity_id, details) FROM stdin;
\.


--
-- Data for Name: donations; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.donations (donation_id, created_at, member_id, provider, provider_reference, amount_cents, currency, donated_at, notes) FROM stdin;
\.


--
-- Data for Name: events; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.events (event_id, created_at, type, name, starts_at, ends_at, location, notes) FROM stdin;
\.


--
-- Data for Name: member_agreements; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.member_agreements (member_agreement_id, created_at, agreement_template_id, signed_at, signature_method, evidence_url, verified_by, verified_at, status, facilitator_id, member_signed_at, facilitator_signed_at, opensign_document_id, evidence, member_id) FROM stdin;
49d242d3-fbf2-4092-833a-17bab244c6a5	2026-01-01 17:00:52.381485+00	fe1f6fcd-6e64-4df0-a49b-0619b83e2735	\N	paper	\N	\N	\N	pending_review	7fe71ad9-e770-49f2-84f1-019781854d90	\N	\N	\N	[[{"path": "download/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_qS666.png", "size": 170309, "title": "Dark_Room_button1.png", "width": 1920, "height": 1040, "mimetype": "image/png", "signedPath": "dltemp/Op_QNUz01o2GkXST/1767294600000/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_qS666.png"}]]	b94c0644-3278-4ecc-9f27-4b8ba917cd9d
43d0a9ae-e803-4d89-ac58-4ed0fc11b661	2026-01-01 17:02:44.683751+00	fe1f6fcd-6e64-4df0-a49b-0619b83e2735	\N	paper	\N	\N	\N	pending_review	7fe71ad9-e770-49f2-84f1-019781854d90	\N	\N	\N	[[{"path": "download/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_XW1SA.png", "size": 168935, "title": "Dark_Room.png", "width": 1920, "height": 1040, "mimetype": "image/png", "signedPath": "dltemp/aKW5nk_eKhI4wG0H/1767294600000/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_XW1SA.png"}, {"path": "download/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_HlCNN.png", "size": 170309, "title": "Dark_Room_button1.png", "width": 1920, "height": 1040, "mimetype": "image/png", "signedPath": "dltemp/FmrwRk5HlHX11L0g/1767294600000/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_HlCNN.png"}], [{"path": "download/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_lGtf3.png", "size": 168935, "title": "Dark_Room.png", "width": 1920, "height": 1040, "mimetype": "image/png", "signedPath": "dltemp/UtpE2DuspbTUVAKp/1767294600000/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_lGtf3.png"}, {"path": "download/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_V8EaC.png", "size": 170309, "title": "Dark_Room_button1.png", "width": 1920, "height": 1040, "mimetype": "image/png", "signedPath": "dltemp/RT8PvHWjpQrDk1jF/1767294600000/2026/01/01/3f68eb00b1198a9c873a6e7a4cbb6189f81617b5/Dark_Room_button1_V8EaC.png"}]]	7b01a0e8-699c-4199-a974-6fe8a62c32a0
abad2e98-b656-4da1-a9e6-75d31f4f44a1	2026-01-01 17:03:32.337942+00	fe1f6fcd-6e64-4df0-a49b-0619b83e2735	\N	opensign	\N	\N	\N	pending_signature	7fe71ad9-e770-49f2-84f1-019781854d90	\N	\N	\N	[]	5bde1e3d-d0d2-48b8-9601-1006af880ed6
\.


--
-- Data for Name: members; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.members (member_id, created_at, updated_at, status, first_name, last_name, email, phone, date_of_birth, notes, is_facilitator, is_document_reviewer) FROM stdin;
7fe71ad9-e770-49f2-84f1-019781854d90	2026-01-01 16:59:06.91017+00	2026-01-01 16:59:06.91017+00	active	Ray	Danks	ray@edanks.com	(303) 887-6965	\N	\N	t	f
b94c0644-3278-4ecc-9f27-4b8ba917cd9d	2026-01-01 17:00:51.667932+00	2026-01-01 17:00:51.667932+00	active	Tst	User	rdanks@wsfr.us	(303) 887-6962	\N	\N	f	f
7b01a0e8-699c-4199-a974-6fe8a62c32a0	2026-01-01 17:02:41.778697+00	2026-01-01 17:02:41.778697+00	active	Another	Test	test@test.com	(333) 994-3333	\N	\N	f	f
5bde1e3d-d0d2-48b8-9601-1006af880ed6	2026-01-01 17:03:32.166004+00	2026-01-01 17:03:32.166004+00	active	Yet	Another	sales@danks.net	(333) 888-3373	\N	\N	f	f
\.


--
-- Data for Name: sacrament_releases; Type: TABLE DATA; Schema: public; Owner: signaturegate
--

COPY public.sacrament_releases (
  sacrament_release_id,
  created_at,
  released_at,
  member_id,
  event_id,
  mushroomprocess_product_id,
  item_name,
  quantity,
  unit,
  released_by,
  notes,
  facilitator_id,
  net_weight_g,
  strain,
  release_type,
  member_agreement_id,
  storage_location_name,
  status,
  voided_at,
  voided_by,
  void_reason
) FROM stdin;


--
-- Name: agreement_templates agreement_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.agreement_templates
    ADD CONSTRAINT agreement_templates_pkey PRIMARY KEY (agreement_template_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_log_id);


--
-- Name: donations donations_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_pkey PRIMARY KEY (donation_id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (event_id);


--
-- Name: member_agreements member_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_pkey PRIMARY KEY (member_agreement_id);


--
-- Name: members members_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_pkey PRIMARY KEY (member_id);


--
-- Name: sacrament_releases sacrament_releases_pkey; Type: CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.sacrament_releases
    ADD CONSTRAINT sacrament_releases_pkey PRIMARY KEY (sacrament_release_id);


--
-- Name: idx_member_agreements_facilitator; Type: INDEX; Schema: public; Owner: signaturegate
--

CREATE INDEX idx_member_agreements_facilitator ON public.member_agreements USING btree (facilitator_id, created_at DESC);


--
-- Name: idx_members_facilitator_active; Type: INDEX; Schema: public; Owner: signaturegate
--

CREATE INDEX idx_members_facilitator_active ON public.members USING btree (is_facilitator, status);


CREATE INDEX idx_member_agreements_member_status
  ON public.member_agreements (member_id, status);

CREATE INDEX idx_sacrament_releases_product_id
  ON public.sacrament_releases (mushroomprocess_product_id);

CREATE INDEX idx_sacrament_releases_member_id
  ON public.sacrament_releases (member_id);

CREATE INDEX idx_sacrament_releases_release_type
  ON public.sacrament_releases (release_type);

CREATE INDEX idx_sacrament_releases_status
  ON public.sacrament_releases (status);


--
-- Name: members trg_members_updated_at; Type: TRIGGER; Schema: public; Owner: signaturegate
--

CREATE TRIGGER trg_members_updated_at BEFORE UPDATE ON public.members FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: donations donations_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);

ALTER TABLE ONLY public.sacrament_releases
  ADD CONSTRAINT sacrament_releases_facilitator_id_fkey
  FOREIGN KEY (facilitator_id)
  REFERENCES public.members(member_id);

ALTER TABLE ONLY public.sacrament_releases
  ADD CONSTRAINT sacrament_releases_member_agreement_id_fkey
  FOREIGN KEY (member_agreement_id)
  REFERENCES public.member_agreements(member_agreement_id);

ALTER TABLE ONLY public.sacrament_releases
  ADD CONSTRAINT sacrament_releases_voided_by_fkey
  FOREIGN KEY (voided_by)
  REFERENCES public.members(member_id);


--
-- Name: member_agreements member_agreements_agreement_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_agreement_template_id_fkey FOREIGN KEY (agreement_template_id) REFERENCES public.agreement_templates(agreement_template_id);


--
-- Name: member_agreements member_agreements_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES public.members(member_id);


--
-- Name: member_agreements member_agreements_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: sacrament_releases sacrament_releases_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.sacrament_releases
    ADD CONSTRAINT sacrament_releases_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(event_id);


--
-- Name: sacrament_releases sacrament_releases_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: signaturegate
--

ALTER TABLE ONLY public.sacrament_releases
    ADD CONSTRAINT sacrament_releases_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- PostgreSQL database dump complete
--

\unrestrict AaemyxLdH6D532qegYS9nNGYrwtDFJ42sIdnh1jweTVvOl9ZHuHvssVdTI6KFh8

