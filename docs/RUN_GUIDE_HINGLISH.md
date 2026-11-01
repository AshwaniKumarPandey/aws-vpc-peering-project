# Run guide (Hinglish)

1. AWS access chahiye: console login ho ya na ho, **CLI credentials** (Access Key + Secret) se bhi chalega.
   `aws configure` -> region `ap-south-1`.
   (Console login fix ho jaye to AWS **CloudShell** me seedha chalta hai: repo upload/clone karke scripts run karo.)
2. `scripts/00-config.env` me `STUDENT_NAME` apna naam daalo.
3. Scripts ko order me run karo: 01 -> 02 -> 03 -> 04 -> 05.
4. Har step ke baad `evidence/` me real output ban jata hai. AWS console ke screenshots bhi lo
   (route tables, peering Active, SG rules, instances me public IP empty).
5. Evidence + screenshots save hone ke BAAD hi `99-cleanup.sh` chalao (same din, warna charges lag sakte hain).
6. Repo GitHub pe push karo (`*.pem` aur `state.env` ignore ho jate hain).
7. Report PDF `YourName_EWB_VPC_Peering.pdf` banao (`docs/REPORT_TEMPLATE.md` follow karo).
