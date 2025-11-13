# COMP2137

# Assignment #1

### system-report.sh
Generates a concise system information report. It prints OS details, uptime, CPU, RAM, disks, video card, host IP, gateway, DNS, logged-in users, disk space, process count, load averages, listening ports, and firewall status.  
On laptops, it also reports **battery health** by comparing the current full charge to the design capacity. On desktops or virtual machines, it will indicate that no battery is detected.

# Assignment 2

## Overview
This repository contains the script and supporting files for Assignment 2.  
The goal is to configure networking for `server1`, ensure services are running, and validate the setup with the provided checker.  
It also includes a system reporting script that generates a concise overview of the host machine, including battery health if available.

## Files

### assignment2.sh
Main script that I delevoped which configures the network settings for `server1`. It creates or updates the netplan configuration, ensures the correct IP address and gateway are set, updates `/etc/hosts`, and disables conflicting netplan files. Installs Apache2 and Squid. Creates 10 users with /home directories and SSH-keys. This script has checkes and balances so if the program runs again it won't overwrite configurations unless intentional.

### check-assign2-script.sh
Checker script provided with the assignment. It runs automated tests against `assignment2.sh` to verify that the network configuration and services meet the assignment requirements.

### check-assign2-errors.txt
Helper script that captures and reports errors encountered during the checking process. Useful for debugging and ensuring that any issues with the configuration are identified and corrected.

### check-assign2-output.txt
Standard output from running the checker. Provides a record of the results, including success messages or warnings, and complements the error log.

### makecontainers.sh & comp2137funcs.sh
Professor provided script which create containers for testing with tools and functions.

