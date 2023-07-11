# vpnserver

This script is to be run on a new EC2 instance when you want VPN access to a VPC.

## Set up EC2 Instance

- Type:  t4g.nano  (arm)
  - amazon linux
  - naming template:   efw.vpn.kp.001
  - use desired vpc

- match subnet corresponding to vpc

- security group - needs 2 inbound rules:
   - SSH (TCP port 22) from your IP address for administration.
   - Custom UDP Rule (port 11094) from anywhere for the OpenVPN server.

- Advanced / Networking
  - disable auto assign public ip
  - allocate an Elastic IP address for this server and make note of it.

- key: Create a new key for access to this instance
  - for logging on to server
  - needs to be saved to secrets manager using this naming template:  vpn-default-vpc-02
  - WHERE IS IT?  - auto-downloaded during instance creation
  - on linux you need to   chmod 400 <vpn-vpc-01.pem>
       
- Give instance a role:   efw.role.vpn 
  - only policy is to read secrets manager
  - create this role if it doesn't exist

- Allow tags in instance metadata: set to "Allow"
  - Add a tag to the instance:
  - Name:   (server name)
  - BackupPlan: LiveResources

## Log in and run script

At this point, you should have the following handy:

- instance name:  vpn-prod-rds
- subnet: (9bb881c0)  172.90.0.0
- ip range: 172.90.10.0 *
- security group: (sg-1234abcd)
- public ip: 54.211.69.96

The IP range is the starting address which the VPN server will begin allocating internal IPs to clients. Should be in the same subnet. By convention we use x.x.10.0.

**Log in to the instance using SSH**. You should have automatically downloaded a *.pem file when you created a key for the server. If using Windows, use *puttyGen* to convert the PEM key to a PPK file.

  ssh -i "vpn-prod-rds.pem" ec2-user@54.241.57.39

After logging in, you will be in the /home/ec2-user directory. Become root.

  sudo su

And download the script:

  wget -O install.sh https://raw.githubusercontent.com/Eightfold-Way-Consultants/vpnserver/master/install.sh

  chmod +x install.sh

**Run the script**

  ./install.sh



