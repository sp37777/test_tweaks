#!/bin/bash
wget https://dl.pstmn.io/download/latest/linux_64
sudo tar xJf linux_64 -C /opt/
sudo ln -s /opt/Postman/Postman /usr/local/bin/postman
postman
