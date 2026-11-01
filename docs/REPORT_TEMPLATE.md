# Report template  →  export as **YourName_EWB_VPC_Peering.pdf**

Use Word/Google Docs: paste the headings below, add YOUR screenshots (label each with host, test, result), then File → Download → PDF.
Do NOT include the .pem key, passwords or access tokens.

## 1. Cover
Name | Batch | Project: AWS VPC Peering | Region: ap-south-1 | Completion date

## 2. Architecture + inventory
- Architecture diagram (README mermaid diagram, or draw.io screenshot)
- Table of ACTUAL IDs: VPC A, VPC B, subnets, route tables, IGW, SGs, instances, pcx-…, private IPs, bastion public IP
  (Source: `evidence/01-inventory-before-peering.txt` + console screenshot)

## 3. Subnets and route tables
- Screenshot: subnet CIDRs
- Screenshot: all three route tables WITH subnet associations (Checkpoint 01 + 04)
  (Source: `evidence/03-peering-and-routes.txt`)

## 4. Peering + security groups
- Screenshot: ewb-a-b-peer = Active, both VPC IDs (Checkpoint 03)
- Screenshot: inbound rules of each SG

## 5. Tests
| Test | Screenshot / file |
|---|---|
| Baseline failure (before peering) | evidence/02 |
| Forward ping A→B | evidence/04 |
| Reverse ping B→A | evidence/04 |
| SSH to App-B through bastion | evidence/04 |
| No public IPv4 on App-A / App-B (EC2 console) | screenshot |

## 6. Controlled failure + recovery
Screenshots from evidence/05 + this explanation:
"I removed only the ICMP echo-request rule (source 10.10.2.10/32) from ewb-sg-app-b. The security group then dropped the ping, so App-A got 100% packet loss even though routes and peering were fine. After restoring the exact rule the replies resumed. This proves peering + routes give a path, but security groups decide whether traffic is allowed."

## 7. Forward path and return path (short explanation)
Forward: App-A (10.10.2.10) → ewb-rt-a-private has 10.20.0.0/16 → pcx → VPC B → App-B; ewb-sg-app-b allows ICMP from 10.10.2.10/32.
Return: App-B → ewb-rt-b-private has 10.10.0.0/16 → pcx → VPC A. Without this return route the replies would be lost.

## 8. Viva questions – short answers
1. **Why is the return route needed?** Peering is not automatic routing. The reply packet from App-B needs a route to 10.10.0.0/16 via the pcx, otherwise it has no path back (one-way route = failed ping).
2. **Why is the App-B SSH source the bastion private IP?** With ProxyJump, the bastion opens a new SSH connection to App-B, so App-B sees the bastion's private IP 10.10.1.10 as source, not my laptop.
3. **Why does Active peering not guarantee ping?** Active only means the link exists. Routes in both route tables and security group rules (ICMP) (and NACLs) must also allow the traffic.
4. **Can VPC B use VPC A's internet gateway over peering?** No. VPC peering does not support edge-to-edge routing through the IGW; peering is non-transitive.

## 9. Cleanup evidence + what I learned
- evidence/06-cleanup-verification.txt + console screenshot showing nothing left
- 3–4 lines of your own learnings (see README "Key learnings")
