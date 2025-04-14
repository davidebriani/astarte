#!/bin/bash

# Uninstall root CA so that it isn't trusted by the local system and browsers
mkcert -uninstall

# Delete the kubernetes cluster
minikube delete
