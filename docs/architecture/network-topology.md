VPC: dbks-infra, CIDR 10.0.0.0/16, DNS Resolution: Enabled, DNS Hostnames: Enabled
    - public subnet 1 (dbks-infra-dev-public-subnet):
        ipv4 CIDR : 10.0.0.0/24
        availability zone : use2-az1 (us-east-2a)
        route table (attached): dbks-infra-dev-public-rt
            - routes : 
                destination: 0.0.0.0/0, target: Internet Gateway (dbks-infra-dev-IGW)
                destination: 10.0.0.0/16, target: local
            - subnet associations: 
                public subnet: dbks-infra-dev-public-subnet
            - edge associations:
            - route propagations:
    - private subnet 1 (dbks-infra-dev-private-subnet):
        ipv4 CIDR: 10.0.1.0/24
        availability zone: use2-az2 (us-east-2b)
        route table (attached): dbks-infra-dev-private-rt
            - routes: 
                destination: 0.0.0.0/0, target: NAT gateway (dbks-infra-dev-NATG)
                destination: 10.0.0.0/16, target: local
            - subnet associations:
                private subnet: dbks-infra-dev-private-subnet
                private subnet: dbks-infra-dev-private-subnet-2
            - edge associations:
            - route propagations:
    - private subnet 2 (dbks-infra-dev-private-subnet-2):
        ipv4 CIDR: 10.0.2.0/24
        availability zone: use2-az1 (us-east-2a)
        route table (attached): dbks-infra-dev-private-rt
            - routes: 
                destination: 0.0.0.0/0, target: NAT gateway (dbks-infra-dev-NATG)
                destination: 10.0.0.0/16, target: local
            - subnet associations:
                private subnet: dbks-infra-dev-private-subnet
                private subnet: dbks-infra-dev-private-subnet-2
            - edge associations:
            - route propagations:
    - Main network ACL:
        inbound rules: 
            - Rule number : 99
                Type: All traffic 
                Protocol: All
                Port Range: All 
                Source: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: *
                Type: All traffic
                Protocol: All
                Port Range: All
                Source: 0.0.0.0/0
                Allow/Deny: Deny
        outbound rules:
            - Rule number: 99
                Type: All traffic
                Protocol: All
                Port Range: All
                Destination: 10.0.0.0/16
                Allow/Deny: Allow
            - Rule number: 100
                Type: HTTPS
                Protocol: TCP
                Port Range: 443
                Destination: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: 101
                Type: MySQL/Aurora
                Protocol: TCP
                Port Range: 3306
                Destination: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: 102
                Type: HTTPS*
                Protocol: TCP
                Port Range: 8443
                Destination: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: 103
                Type: Custom TCP
                Protocol: TCP
                Port Range: 8445
                Destination: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: 104
                Type: Custom TCP
                Protocol: TCP
                Port Range: 8444
                Destination: 0.0.0.0/0
                Allow/Deny: Allow
            - Rule number: *
                Type: All traffic
                Protocol: All
                Port Range: All
                Destination: 0.0.0.0/0
                Allow/Deny: Deny
        Subnet Associations:
            - name: dbks-infra-dev-public-subnet
            - name: dbks-infra-dev-private-subnet-2
            - name: dbks-infra-dev-private-subnet
    DHCP option set: 
        - name : dbks-infra-dev-DHCP-option-set
        - Domain name : us-east-2.compute.internal
        - Domain name servers: AmazonProvidedDNS
    
    Internet Gateway: dbks-infra-dev-IGW
    NAT Gateway: dbks-infra-dev-NATG
        - Primary public IPv4 address: 16.59.107.134
        - Subnet : dbks-infra-dev-public-subnet
        - Primary private IPV4 address: 10.0.0.79
        - Primary network interface:
            name: dbks-infra-dev-primary-network-interface






