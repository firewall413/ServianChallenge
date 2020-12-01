# Servian DevOps Tech Challenge - Tech Challenge App


## Prerequisites

Software dependencies:
- Terraform v0.13.5
- Terragrunt v0.23.40
- AWS CLI

AWS dependencies:
- IAM role needs to be set up with Admin rights, key & secret saved in /.aws credentials file (https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html)
- AWS CLI needs to be configured with this profile (aws cli configure)
- The following SSM Parameters need to be present: \
  servianchallenge_postgresdb_user = postgres\
  servianchallenge_postgresdb_pw = dbpass1234
- The following s3 bucket needs to be created:\
servian-challenge-terraformstate


## Usage

- Clone Repository: https://github.com/firewall413/ServianChallenge.git
- Run "terragrunt apply-all" in folder ./ServianChallenge/Terraform (Build can take +15 mins)
- Console will output ALB DNS endpoint, copy in browser to test service (If a 503 occurs, give the container a couple more seconds to spin up) 

## Improvements to make production ready

Be mindful that this solution is not a production-grade service. Trying to showcase my technical abilities while meeting the requirements sometimes meant I went for a more complex architecture (ECS vs EC2, multi-az,...) or less costly AWS feature (simple ALB endpoint vs route 53/domain name). Below I've documented a couple of my design decisions and tweaks I would implement to elevate this to a production-grade service.

#### Cost reduction
- Depending on the nature of the service we might not need 3 availability zones, 2 might suffice. (reduces the # of EIPs, NGWs,...)
- RDS could be overkill for this application (Amazon SimpleDB might be sufficient for a simple To-Do list)

#### High Availability/Security
- Set up NAT Gateways & elastic IPs in all AZs to prevent outage if AZ-1 goes down (Only implemented 1 for demo purposes)
- Set up HTTPS certifcate, purchase an actual hostname, set ALB Listener on port 443 and forward it to 80 on the ECS cluster target group

#### CI/CD
- Instead of using the original servian/techchallengeapp Docker image, I rebuilt it to allow for sequential sh commands (updatedb -s, serve) at ENTRYPOINT on container runtime as the image did not contain Bash or sh. I was not sure if this was allowed.
- Switch from Launch Configuration to Launch Templates (if this service/app would need to be changed/updated often)
- Improve naming conventions, add tags for Terraform/AWS resources (Depends heavily on project/company/setup, for demo purposes I went with short & simple)
- Integrate with CI/CD workflow (for demo purposes I used Terragrunt/Terraform as the requirements stated to not use superfluous dependencies)
