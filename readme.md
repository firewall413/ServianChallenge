# Servian DevOps Tech Challenge - Tech Challenge App


## Prerequisites

Software dependencies:
- Terraform v0.13.5
- Terragrunt v0.23.40
- AWS CLI

AWS dependencies:
- IAM role needs to be set up with Admin rights, key & secret saved in .aws credentials file https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html
- AWS CLI needs to be configured with this profile (aws cli configure)
- The following SSM Parameters need to be present: 
servianchallenge_postgresdb_user = postgres
servianchallenge_postgresdb_pw = dbpass1234
- The following s3 bucket needs to be created & have RW permissions:
"servian-challenge-terraformstate"


## Usage

- Clone Repository: https://github.com/firewall413/ServianChallenge.git
- Run "terragrunt apply-all" in root folder ./ServianChallenge
- ALB DNS endpoint will be output in console -> test service

## Improvements to make production ready

Be mindful that this solution is not a production-grade service. Trying to showcase my technical abilities while meeting the requirements sometimes meant I went for a more complex solution (ECS vs EC2) or less expensive design choice (just ALB endpoint vs route 53/domain name). Below I've documented a couple of my design decisions and tweaks I would implement to elevate this to a production-grade service.

- Depending on the nature of the service we might not need 3 availability zones, 2 might suffice.
- Set up NAT Gateways & elastic IPs in all AZs to prevent outage if AZ-1 goes down (Only implemented 1 for demo purposes)
- Set up HTTPS certifcate, purchase an actual hostname, set ALB Listener on port 443 and forward it to 80 on the ECS cluster target group
- RDS is overkill for this application (Amazon SimpleDB might be sufficient)
- Switch from Launch Configuration to Launch Templates (if this service/app would need to be changed/updated often)
- Improve naming conventions, add tags for Terraform/AWS resources (Depends heavily on project/company/setup, for demo purposes I went with short & simple)
- Integrate with CI/CD workflow (for demo purposes I used Terragrunt/Terraform as the requirements stated to not use superfluous dependencies)
