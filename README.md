[![Open in Visual Studio Code](https://classroom.github.com/assets/open-in-vscode-c66648af7eb3fe8bc4f294546bfd86ef473780cde1dea487d3c4ff354943c9ae.svg)](https://classroom.github.com/online_ide?assignment_repo_id=8283340&assignment_repo_type=AssignmentRepo)
1. Create a vault contract 

2. Ensure deposits can be made and withdrawn 

3. A successful payment from a Vault will require 3 steps: 
STEP 1: The owner adds approvedSpenders to the whitelist. 
STEP 2: An approvedSpender will authorize a payment. 
STEP 2.5: The payment will have to wait out the specified timeDelay. 
STEP 3: The payment’s recipient can call collectAuthorizedPayment() to be sent the ether 

4. Ensure the Vault Contract has basic security features 

4.1. Whitelist: Only addresses that have been pre-approved by the owner can authorize a payment, this is NOT an optional feature. The owner can remove addresses from the whitelist as well (The owner role however IS optional, after it has added authorizedSpenders to the whitelist, it can be set to 0x0). 

4.2. Time-Based Failsafes: Authorized Payments cannot be collected until the earliestPayTime has passed. The minimum earliestPayTime is set when deploying the Vault (and can be set to 0 to allow immediate payments) but it can be extended by: 
A. The owner (only affects future authorized payments) 
B. The approvedSpender when authorizing a payment. 
C. The securityGuard anytime after the payment has been authorized. 

4.3. Canceling Authorized Payments: The ‘owner’ can cancel any authorized payment. 

4.4. Escape Hatch: If there seems to be a critical issue, the owner or the escapeCaller can call the escapeHatch() to send the ether in the Vault to a trusted multisig (specified when deploying the Vault and of course this is also a completely optional feature). 

5. Deploy repo and submit to trainer for review
