# vpnserver

This script is to be run on a new EC2 instance when you want VPN access to a VPC.

## Set up EC2 Instance

You can use the EC2 template:  **EFW_VPN_Template**

- Type:  t4g.nano  (arm)
  - amazon linux
  - our (ideal) naming template:   vpn-[VPC NAME]-[VPC-FUNCTION]   for example: vpn-vpc01-vault
  - use desired vpc

- match subnet corresponding to vpc

- security group - needs 2 inbound rules:
   - SSH (TCP port 22) from your IP address for administration. You could disable this after the initial setup.
   - Custom UDP Rule (port 11094) from anywhere for the OpenVPN server.

- Advanced / Networking
  - disable auto assign public ip
  - allocate an Elastic IP address for this server and make note of it.

- key: Create a new key for access to this instance
  - for logging on to server
  - use the .pem file format
  - needs to be saved to secrets manager using this naming template:  vpn-default-vpc-02
  - WHERE IS IT?  - auto-downloaded during instance creation
  - on linux you need to   chmod 400 <vpn-vpc-01.pem>
       
- Give instance a role:   efw.role.vpn 
  - only policy is to read/write secrets manager
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

The IP range is the starting address which the VPN server will begin allocating internal IPs to clients. Should be in the same subnet. By convention we use x.x.10.0. The final digit needs to be 0. 

**Log in to the instance using SSH**. You should have automatically downloaded a *.pem file when you created a key for the server. If using Windows, use *puttyGen* to convert the PEM key to a PPK file.

If using linux, set the permission on the .pem file:

    chmod 400 vpn-prod-rds.pem.pem
    
And log in:

    ssh -i "vpn-prod-rds.pem" ec2-user@54.241.57.39

After logging in, you will be in the /home/ec2-user directory. Become root.

    sudo su

And download the script:

    wget -O install.sh https://raw.githubusercontent.com/Eightfold-Way-Consultants/vpnserver/master/install.sh

    chmod +x install.sh

**Run the script**

    ./install.sh

A few minutes will pass as it installs software. Eventually it will prompt you for the info you have noted above. It is important to pay close attention and paste the correct item.

## The VPN install script

The script is split into 5 steps. When it successfully passes a step, it updates the `install_status.txt` file. If a step fails, the script will attempt to continue from that step on subsequent invocations.

**Step 1**: All of the necessary software is downloaded and installed.

**Step 2**: openvpn and easy-rsa are compiled and installed.  Some organization level variables are saved to a config file in `/etc/openvpn/pki/vars`.

**Step 3**: User is asked for the specific details of this server.

- server's name
- public ip address
- starting ip address to assign to vpn clients (*This should end in zero. Ex: 172.90.10.0*)

A passphrase is created and uploaded to a new *secret* in AWS Secrets Manager. 

Remember to open this new secret in the AWS web console, and add your .pem file.

**Step 4**: The certificates for openvpn and easyrsa are built. These certificates are located in various places in `/etc/openvpn/easy-rsa/pki/`. They are signed with the server's name and only to be used on this particular instance. 

**This step is fairly delicate**. You'll need to paste the passphrase back in (twice) without seeing any feedback. If any of the questions get answered wrong, the wrong settings are going to be scattered amongst multiple files. If you make a mistake here, it might be best to wipe the server and start over fresh. Sorry. Openvpn and easyrsa will ask you some stern sounding questions here too. **Pay attention**.

The openvpn configuration file is created at `/etc/openvpn/server.conf`. 

`iptables` is now installed. Finally, a startup script, `start_vpn.sh` is created. It will configure iptables and start the openvpn server. It is configured to run on boot. 

The server is now fully configured. You can reboot now, or run the script at `/etc/init.d/start_vpn.sh`.

## Setup Clients

**Step 5**: From this point on, successive invocations of the script will create a new client for the vpn. You can repeatedly call the script to create new client configurations. 

Creating a new client involves creating a certificate on the server, and a `.ovpn` file, which will need to be downloaded and loaded into the user's vpn configuration. The file `/etc/openvpn/easy-rsa/$clientname-$servername.ovpn` is created and uploaded to a new AWS Secret.

- Log in to the AWS Console, and look for a new secret with the name of: `$servername-$clientname`.
- View the 'Secret Value' (which should be plaintext) and copy the contents to a file named `$servername-$clientname.ovpn`
- In your VPN client, create a new configuration by 'import file...' method. Choose the .ovpn you just created.
- You can now connect to the vpn.






