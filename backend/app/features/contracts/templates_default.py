"""Default contract-terms template seeded per company.

IMPORTANT — NOT LEGAL ADVICE. The body below is PLACEHOLDER STRUCTURE modeled on the
sections a California home-improvement contract is expected to contain (see Cal. Bus. &
Prof. Code sec. 7159 for the statutory structure). Every section is marked
[ATTORNEY REVIEW REQUIRED] and MUST be replaced with binding language reviewed by the
company's licensed attorney before any real use. The template is company-editable
precisely so counsel can supply the wording.

Merge fields resolved at contract generation:
  {{company_name}} {{company_address}} {{company_license_number}} {{company_phone}}
  {{client_name}} {{client_address}} {{client_email}} {{project_description}}
  {{quote_number}} {{quote_total}} {{today}} {{validity_statement}} {{payment_schedule}}
"""

DEFAULT_TEMPLATE_NAME = "California Home Improvement Contract (draft)"

DEFAULT_CONTRACT_BODY = """\
<h1>Home Improvement Contract</h1>

<p class="review-banner">[ATTORNEY REVIEW REQUIRED] This document is a structural
placeholder, not legal advice. Replace every section with language reviewed and approved
by your attorney before use.</p>

<h2>1. Parties</h2>
<p>This contract is entered into on {{today}} between <strong>{{company_name}}</strong>
(the "Contractor"), CSLB License No. <strong>{{company_license_number}}</strong>,
{{company_address}}, {{company_phone}}, and <strong>{{client_name}}</strong> (the
"Owner"), {{client_address}}.</p>

<h2>2. Description of the Work</h2>
<p>[ATTORNEY REVIEW REQUIRED] The Contractor will perform the following work and furnish
the following materials: {{project_description}}. Full scope and specifications are set
out in Quote {{quote_number}}, incorporated by reference.</p>

<h2>3. Dates of Performance</h2>
<p>[ATTORNEY REVIEW REQUIRED] Approximate start date: __________. Approximate completion
date: __________.</p>

<h2>4. Contract Price and Schedule of Payments</h2>
<p>[ATTORNEY REVIEW REQUIRED] The total contract price is
<strong>{{quote_total}}</strong>. Payment schedule: {{payment_schedule}}.</p>

<h2>5. Down Payment</h2>
<p>[ATTORNEY REVIEW REQUIRED] Under California law the down payment may not exceed the
lesser of $1,000 or 10% of the contract price, excluding finance charges. State the down
payment amount here: __________.</p>

<h2>6. Notice of the Three-Day Right to Cancel</h2>
<p>[ATTORNEY REVIEW REQUIRED] You, the buyer, have the right to cancel this contract
within three business days (five business days for buyers 65 or older, and longer after a
declared disaster). Insert the statutory notice and attach the required cancellation form
approved by your attorney.</p>

<h2>7. Mechanics' Lien Warning</h2>
<p>[ATTORNEY REVIEW REQUIRED] Insert the California mechanics' lien warning ("Anyone who
helps improve your property, but who is not paid, may record what is called a mechanics'
lien...") exactly as approved by your attorney.</p>

<h2>8. Change Orders</h2>
<p>[ATTORNEY REVIEW REQUIRED] Any change to the work must be in writing and signed by both
parties before the changed work begins.</p>

<h2>9. Dispute Resolution</h2>
<p>[ATTORNEY REVIEW REQUIRED] Insert the dispute-resolution / arbitration provision
approved by your attorney, including any statutorily required arbitration disclosures.</p>

<h2>10. Validity</h2>
<p>{{validity_statement}}</p>

<h2>11. Acceptance</h2>
<p>By signing below, the Owner acknowledges having read and received a copy of this
contract, including the notices above, and agrees to its terms.</p>
"""
