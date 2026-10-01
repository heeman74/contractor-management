"""Default contract-terms template seeded per company.

Follows the Contractors State License Board's published sample Home Improvement
Contract, which is the structure California expects under Cal. Bus. & Prof. Code
sec. 7159. The statutory notices — the mechanics lien warning, the downpayment
cap, the progress-payment warning, the CSLB information block and the right-to-
cancel notices — are reproduced as CSLB publishes them, because those are the
parts a contractor is not free to paraphrase.

NOT LEGAL ADVICE. CSLB publishes this sample for information only, without
warranty of accuracy or suitability for any particular project, and so does this
copy of it. Everything a specific job needs — the scope, the dates, the payment
schedule, the insurance answers — is left as a blank to fill, and the whole
document should be reviewed by the company's own attorney before use. The
template is company-editable precisely so counsel can change it.

Only one right-to-cancel period applies to a given contract. All three notices
are included under CSLB's own "USE THESE NOTICES IF…" headings, so whoever
prepares the contract keeps the one that applies and deletes the others.

Merge fields resolved at contract generation:
  {{company_name}} {{company_address}} {{company_license_number}} {{company_phone}}
  {{company_email}} {{client_name}} {{client_address}} {{client_email}}
  {{project_description}} {{quote_number}} {{quote_total}} {{today}}
  {{validity_statement}} {{payment_schedule}}
"""

DEFAULT_TEMPLATE_NAME = "California Home Improvement Contract (CSLB sample)"

DEFAULT_CONTRACT_BODY = """\
<p class="review-banner">Based on the CSLB sample Home Improvement Contract.
Provided for information only and not a substitute for legal advice. Fill in every
blank and have your attorney review this before using it on a real project.</p>

<h1>HOME IMPROVEMENT CONTRACT</h1>

<div class="contractor-block">
  <p class="contractor-name"><strong>{{company_name}}</strong></p>
  <p>The Notice of Cancellation may be mailed or emailed to the contractor at the
  address noted on the contract.</p>
  <p>{{company_address}} &middot; {{company_phone}} &middot; {{company_email}}</p>
  <p>Contractor's License No. <strong>{{company_license_number}}</strong></p>
  <p>Telephone number to assist buyer with locating and completing the Notice of
  Cancellation: {{company_phone}}</p>
</div>

<p>This Agreement signed by the owner and dated <span class="fill">{{today}}</span>
is between <strong>{{company_name}}</strong> ("Contractor") and
<strong>{{client_name}}</strong> ("Owner").</p>

<p><strong>Owner's Address or address where work is performed:</strong>
<span class="fill">{{client_address}}</span></p>

<p>Substantial commencement of work under this contract is described as
<span class="blank"></span></p>

<p><strong>Approximate Start Date:</strong> <span class="blank"></span>
<strong>Approximate Completion Date:</strong> <span class="blank"></span></p>

<p><strong>Contract Price:</strong> Owner agrees to pay Contractor a total cash
price, in dollars and cents, of <strong>{{quote_total}}</strong>.</p>

<p><strong>Finance Charge:</strong> In dollars and cents (if any, if not
applicable, put "none") <span class="blank"></span></p>

<p><strong>Downpayment:</strong> (if any, if not applicable, put "none")
<span class="blank"></span></p>

<p class="statutory">THE DOWNPAYMENT MAY NOT EXCEED $1,000 OR 10 PERCENT OF THE
CONTRACT PRICE, WHICHEVER IS LESS.</p>

<h2>Description of the Project and Description of the Significant Materials to be
Used and Equipment to be Installed</h2>
<p>{{project_description}}</p>
<p>Full scope and specifications are set out in Quote {{quote_number}},
incorporated by reference.</p>
<p class="blank-lines"></p>

<p><strong>Will subcontractors be used on this project?</strong>
<span class="checkbox"></span> Yes &nbsp; <span class="checkbox"></span> No</p>
<p>If yes, upon request, the contractor shall provide a list of subcontractors,
including names, contact information, license numbers, and classifications.</p>

<p><strong>If payment (other than a downpayment) is not due until completion,
check here:</strong> <span class="checkbox"></span> There will be no schedule of
progress payments. Otherwise, include the Schedule of Progress Payments. The
schedule of progress payments must specifically describe each phase of work,
including the type and amount of work or services scheduled to be supplied in each
phase, along with the amount of each proposed progress payment.</p>

<p class="statutory">IT IS AGAINST THE LAW FOR A CONTRACTOR TO COLLECT PAYMENT FOR
WORK NOT YET COMPLETED, OR FOR MATERIALS NOT YET DELIVERED. HOWEVER, A CONTRACTOR
MAY REQUIRE A DOWNPAYMENT.</p>

<h2>Schedule of Progress Payments</h2>
<p>{{payment_schedule}}</p>
<table class="payments">
  <thead>
    <tr>
      <th>AMOUNT (in dollars and cents)</th>
      <th>EVENT (specifically reference the amount of work performed and services,
      materials, and equipment supplied)</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>$</td><td></td></tr>
    <tr><td>$</td><td></td></tr>
    <tr><td>$</td><td></td></tr>
    <tr><td>$</td><td></td></tr>
    <tr><td>$</td><td></td></tr>
    <tr><td>$</td><td>Completion of project</td></tr>
  </tbody>
</table>

<h2>Note About Extra Work and Change Orders</h2>
<p>Extra Work and Change Orders become part of the contract once the order is
prepared in writing and signed by the parties prior to the commencement of work
covered by the new change order. The order must describe the scope of the extra
work or change, the cost to be added or subtracted from the contract, and the
effect the order will have on the schedule of progress payments. Specifically:</p>
<ol>
  <li>You may not require a contractor to perform extra or change order work
  without providing written authorization prior to the commencement of work
  covered by the new change order.</li>
  <li>Extra work or a change order is not enforceable against a buyer unless the
  change order also identifies all of the following in writing prior to the
  commencement of work covered by the new change order: (i) The scope of work
  encompassed by the order. (ii) The amount to be added or subtracted from the
  contract. (iii) The effect the order will make in the progress payments or the
  completion date.</li>
</ol>
<p>If subcontractors are used for the extra work or change order, upon request,
the contractor shall provide a list of subcontractors, including names, contact
information, license numbers, and classifications.</p>
<p>Contractor's failure to comply with the requirements of this paragraph does not
preclude the recovery of compensation for work performed based upon legal or
equitable remedies designed to prevent unjust enrichment.</p>

<h2>Release</h2>
<p>Upon satisfactory payment being made for any portion of the work performed, the
Contractor, prior to any further payment being made, shall furnish to the person
contracting for the home improvement or swimming pool work a full and
unconditional release from any potential lien claimant claim or mechanics lien
authorized pursuant to Sections 8400 and 8404 of the Civil Code for that portion
of the work for which payment has been made.</p>

<h2>List of Documents to be Incorporated into the Contract</h2>
<p>(if none, state none): Notice of Right to Cancellation; Three-Day Right to
Cancel (except if damaged by a disaster OR Homeowner over 65) or Five-Day Right to
Cancel (if contracting Homeowner is over 65) or Seven-Day Right to Cancel (only if
damaged by a disaster); and (if no additional documents, state "none")
<span class="blank"></span></p>
<ul>
  <li>A notice concerning commercial general liability insurance is attached to
  this contract.</li>
  <li>A notice concerning workers' compensation insurance is attached to this
  contract.</li>
</ul>

<h2 class="centered">MECHANICS LIEN WARNING</h2>
<p>Anyone who helps improve your property, but who is not paid, may record what is
called a mechanics lien on your property. A mechanics lien is a claim, like a
mortgage or home equity loan, made against your property and recorded with the
county recorder.</p>
<p>Even if you pay your contractor in full, unpaid subcontractors, suppliers, and
laborers who helped to improve your property may record mechanics liens and sue
you in court to foreclose the lien. If a court finds the lien is valid, you could
be forced to pay twice or have a court officer sell your home to pay the lien.
Liens can also affect your credit.</p>
<p>To preserve their right to record a lien, each subcontractor and material
supplier must provide you with a document called a 'Preliminary Notice.' This
notice is not a lien. The purpose of the notice is to let you know that the person
who sends you the notice has the right to record a lien on your property if they
are not paid.</p>
<p>BE CAREFUL. The Preliminary Notice can be sent up to 20 days after the
subcontractor starts work or the supplier provides material. This can be a big
problem if you pay your contractor before you have received the Preliminary
Notices.</p>
<p>You will not get Preliminary Notices from your prime contractor or from
laborers who work on your project. The law assumes that you already know they are
improving your property.</p>
<p>PROTECT YOURSELF FROM LIENS. You can protect yourself from liens by getting a
list from your contractor of all the subcontractors and material suppliers that
work on your project. Find out from your contractor when these subcontractors
started work and when these suppliers delivered goods or materials. Then wait 20
days, paying attention to the Preliminary Notices you receive.</p>
<p>PAY WITH JOINT CHECKS. One way to protect yourself is to pay with a joint
check. When your contractor tells you it is time to pay for the work of a
subcontractor or supplier who has provided you with a Preliminary Notice, write a
joint check payable to both the contractor and the subcontractor or material
supplier.</p>
<p>For other ways to prevent liens, visit CSLB's internet website at
www.cslb.ca.gov or call CSLB at 800-321-CSLB (2752).</p>
<p>REMEMBER, IF YOU DO NOTHING, YOU RISK HAVING A LIEN PLACED ON YOUR HOME. This
can mean that you may have to pay twice, or face the forced sale of your home to
pay what you owe.</p>

<h2>INFORMATION ABOUT THE CONTRACTORS STATE LICENSE BOARD (CSLB)</h2>
<p>CSLB is the state consumer protection agency that licenses and regulates
construction contractors.</p>
<p>Contact CSLB for information about the licensed contractor you are considering,
including information about disclosable complaints, disciplinary actions, and
civil judgments that are reported to CSLB.</p>
<p>Use only licensed contractors. If you file a complaint against a licensed
contractor within the legal deadline (usually four years), CSLB has authority to
investigate the complaint. If you use an unlicensed contractor, CSLB may not be
able to help you resolve your complaint. Your only remedy may be in civil court,
and you may be liable for damages arising out of any injuries to the unlicensed
contractor or the unlicensed contractor's employees.</p>
<p class="centered">For more information:<br />
Visit CSLB's internet website at www.cslb.ca.gov<br />
Call CSLB at 800-321-CSLB (2752)<br />
Write CSLB at P.O. Box 26000, Sacramento, CA 95826.</p>

<p class="statutory">YOU ARE ENTITLED TO A COMPLETELY FILLED IN COPY OF THIS
AGREEMENT, SIGNED AND DATED BY BOTH YOU AND THE CONTRACTOR, BEFORE ANY WORK MAY BE
STARTED.</p>

<p>You, the Owner or Tenant, have the right to require the contractor to furnish
you with a performance and payment bond.</p>

<p><span class="checkbox"></span> If you are 65 years or older, the law requires
that the Contractor give you a notice explaining your right to cancel. Initial
this checkbox if the Contractor has given you a "Notice of Five-Day Right to
Cancel."</p>
<p><span class="checkbox"></span> If this contract is for the repair or
restoration of residential premises damaged by any sudden or catastrophic event
for which a state of emergency has been declared, the law requires that the
Contractor give you a notice explaining your right to cancel. Initial this
checkbox if the Contractor has given you a "Notice of Seven-Day Right to
Cancel."</p>
<p><span class="checkbox"></span> For all other contracts, the law requires that
the Contractor give you a notice explaining your right to cancel. Initial this
checkbox if the Contractor has given you a "Notice of Three-Day Right to
Cancel."</p>
<p>Your receipt of the copy initiates your right to cancel the contract pursuant
to Sections 1689.5 to 1689.14 of the Civil Code.</p>

<p>{{validity_statement}}</p>

<table class="signatures">
  <tr><th>OWNER</th><th>CONTRACTOR</th></tr>
  <tr><td class="sig-cell">Signature</td><td class="sig-cell">Signature</td></tr>
  <tr><td class="sig-cell">Date</td><td class="sig-cell">Date</td></tr>
  <tr>
    <th>SECOND OWNER if applicable</th>
    <th>Registered Salesperson and Registration Number if Applicable</th>
  </tr>
  <tr><td class="sig-cell">Signature</td><td class="sig-cell">Signature</td></tr>
  <tr><td class="sig-cell">Date</td><td class="sig-cell">Date</td></tr>
</table>

<h2 class="centered">STATUTORY NOTICES</h2>

<h3 class="centered">COMMERCIAL GENERAL LIABILITY INSURANCE (CGL)</h3>
<p><span class="checkbox"></span> This Contractor carries commercial general
liability insurance written by <span class="blank"></span> (the insurance
company). You may call <span class="blank"></span> to check the contractor's
insurance coverage.</p>
<p><span class="checkbox"></span> This Contractor does not carry commercial
general liability insurance.</p>
<p><span class="checkbox"></span> This Contractor is self-insured.</p>
<p><span class="checkbox"></span> This Contractor is a limited liability company
that carries liability insurance or maintains other security as required by law.
You may call <span class="blank"></span> (the insurance company or trust company
or bank) to check on the contractor's insurance coverage or security.</p>

<h3 class="centered">WORKERS' COMPENSATION INSURANCE</h3>
<p><span class="checkbox"></span> This Contractor carries workers' compensation
insurance for all employees.</p>
<p><span class="checkbox"></span> This Contractor has no employees and is exempt
from workers' compensation requirements.</p>

<h2 class="centered page-break">THREE-DAY RIGHT TO CANCEL</h2>
<p>You, the buyer, have the right to cancel this contract within three business
days. You may cancel by e-mailing, mailing, faxing, or delivering a written notice
to the contractor at the contractor's place of business by midnight of the third
business day after you received a signed and dated copy of the contract that
includes this notice. Include your name, your address, and the date you received
the signed copy of the contract and this notice.</p>
<p>If you cancel, the contractor must return to you anything you paid within 10
days of receiving the notice of cancellation. For your part, you must make
available to the contractor at your residence, in substantially as good condition
as you received them, any goods delivered to you under this contract or sale. Or,
you may, if you wish, comply with the contractor's instructions on how to return
the goods at the contractor's expense and risk. If you do make the goods available
to the contractor and the contractor does not pick them up within 20 days of the
date of your notice of cancellation, you may keep them without any further
obligation. If you fail to make the goods available to the contractor, or if you
agree to return the goods to the contractor and fail to do so, then you remain
liable for performance of all obligations under the contract.</p>
<p>I, <span class="blank"></span> (Buyer) hereby acknowledge that on
<span class="blank"></span> (Date) I was provided this document entitled
"Three-Day Right to Cancel."</p>
<p class="sig-right">(Buyer's Signature)</p>

<h2 class="centered">NOTICE OF CANCELLATION</h2>
<p><span class="blank"></span> (Date)</p>
<p>You may cancel this transaction, without any penalty or obligation, within
three business days from the above date.</p>
<p>Telephone number to assist with locating and completing the Notice of
Cancellation: {{company_phone}}</p>
<p>If you cancel, any property traded in, any payments made by you under the
contract or sale, and any negotiable instrument executed by you will be returned
within 10 days following receipt by the seller of your cancellation notice, and
any security interest arising out of the transaction will be canceled.</p>
<p>If you cancel, you must make available to the seller at your residence, in
substantially as good condition as when received, any goods delivered to you under
this contract or sale, or you may, if you wish, comply with the instructions of
the seller regarding the return shipment of the goods at the seller's expense and
risk.</p>
<p>If you do make the goods available to the seller and the seller does not pick
them up within 20 days of the date of your notice of cancellation, you may retain
or dispose of the goods without any further obligation. If you fail to make the
goods available to the seller, or if you agree to return the goods to the seller
and fail to do so, then you remain liable for performance of all obligations under
the contract.</p>
<p>To cancel this transaction, email, fax, mail, or deliver a signed and dated
copy of this cancellation notice, or any other written notice, or send a telegram
to <strong>{{company_name}}</strong> at {{company_address}}, email:
{{company_email}}, not later than midnight of <span class="blank"></span>
(Date).</p>
<p>I hereby cancel this transaction. <span class="blank"></span> (Date)</p>
<p class="sig-right">(Buyer's Signature)</p>

<h2 class="centered page-break">USE THESE NOTICES IF EITHER CONTRACTING OWNER IS
65 YEARS OR OLDER</h2>
<h3 class="centered">FIVE-DAY RIGHT TO CANCEL</h3>
<p>You, the buyer, have the right to cancel this contract within five business
days. You may cancel by e-mailing, mailing, faxing, or delivering a written notice
to the contractor at the contractor's place of business by midnight of the fifth
business day after you received a signed and dated copy of the contract that
includes this notice. Include your name, your address, and the date you received
the signed copy of the contract and this notice.</p>
<p>If you cancel, the contractor must return to you anything you paid within 10
days of receiving the notice of cancellation. The same obligations about making
goods available, and the same 20-day limit on the contractor collecting them,
apply as in the Three-Day notice above.</p>
<p>I, <span class="blank"></span> (Buyer) hereby acknowledge that on
<span class="blank"></span> (Date) I was provided this document entitled
"Five-Day Right to Cancel."</p>
<p class="sig-right">(Buyer's Signature)</p>

<h2 class="centered page-break">USE THESE NOTICES IF THIS CONTRACT IS FOR THE
REPAIR OR RESTORATION OF RESIDENTIAL PREMISES DAMAGED BY ANY SUDDEN OR
CATASTROPHIC EVENT FOR WHICH A STATE OF EMERGENCY HAS BEEN DECLARED</h2>
<h3 class="centered">SEVEN-DAY RIGHT TO CANCEL</h3>
<p>You, the buyer, have the right to cancel this contract within seven business
days. You may cancel by e-mailing, mailing, faxing, or delivering a written notice
to the contractor at the contractor's place of business by midnight of the seventh
business day after you received a signed and dated copy of the contract that
includes this notice. Include your name, your address, and the date you received
the signed copy of the contract and this notice.</p>
<p>If you cancel, the contractor must return to you anything you paid within 10
days of receiving the notice of cancellation. The same obligations about making
goods available, and the same 20-day limit on the contractor collecting them,
apply as in the Three-Day notice above.</p>
<p>I, <span class="blank"></span> (Buyer) hereby acknowledge that on
<span class="blank"></span> (Date) I was provided this document entitled
"Seven-Day Right to Cancel."</p>
<p class="sig-right">(Buyer's Signature)</p>
"""
