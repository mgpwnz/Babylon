#!/bin/bash
while true
do
# Menu
PS3='Select an action: '
options=("Pre-download" "Download the components" "Create the configuration" "logs" "Create wallet" "Balance check" "Create BLS key" "Status"  "Run Validator"  "Uninstall" "Exit")
select opt in "${options[@]}"
               do
                   case $opt in                          
"Pre-download")
#update
sudo apt update && sudo apt upgrade -y
#libs
sudo apt install -y unzip  gcc make logrotate git jq lz4 sed wget curl build-essential coreutils systemd
#go
cd $HOME
! [ -x "$(command -v go)" ] && {
VER="1.20.3"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz" &> /dev/null
sudo rm -rf /usr/local/go &> /dev/null
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz" &> /dev/null
rm "go$VER.linux-amd64.tar.gz" &> /dev/null
[ ! -f ~/.bash_profile ] && touch ~/.bash_profile
echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source $HOME/.bash_profile
}
break
;;
"Download the components")
# Clone repository
cd $HOME
git clone https://github.com/babylonchain/babylon.git
cd $HOME/babylon
git checkout v0.7.2
make build
cd $HOME/babylon/build/
cp ./babylond /usr/local/bin/
cd
break
;;
"Create the configuration")
#ini
if [ ! $MONIKER ]; then
		read -p "Enter Moniker: " MONIKER
		echo 'export MONIKER='$MONIKER} >> $HOME/.bash_profile
	fi
. $HOME/.bash_profile
babylond config chain-id bbn-test-2
babylond config keyring-backend test
babylond init $MONIKER --chain-id bbn-test-2
#snap
curl -Ls https://snapshots.kjnodes.com/babylon-testnet/genesis.json > $HOME/.babylond/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/babylon-testnet/addrbook.json > $HOME/.babylond/config/addrbook.json
#config
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@babylon-testnet.rpc.kjnodes.com:16459\"|" $HOME/.babylond/config/config.toml

sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.00001ubbn\"|" $HOME/.babylond/config/app.toml

sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
  $HOME/.babylond/config/app.toml
#service
sudo tee /etc/systemd/system/babylond.service > /dev/null << EOF

[Unit]
Description=Babylon Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which babylond) start
Restart=on-failure
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF
sleep 1
babylond tendermint unsafe-reset-all --home $HOME/.babylond --keep-addr-book
#run service
sudo systemctl daemon-reload
sudo systemctl enable babylond
sudo systemctl start babylond
echo "sudo journalctl -u babylond -f --no-hostname -o cat"

break
;;
"Run Validator")
babylond tx checkpointing create-validator \
--amount 1000000ubbn \
--pubkey $(babylond tendermint show-validator) \
--moniker "$MONIKER" \
--chain-id bbn-test-2 \
--commission-rate 0.1 \
--commission-max-rate 0.20 \
--commission-max-change-rate 0.01 \
--min-self-delegation 1 \
--from wallet \
--gas-adjustment 1.4 \
--gas auto \
--gas-prices 0.00001ubbn \
-y
break
;;

"Status")
echo "false - значит нода синхронизирована"
babylond status | jq .SyncInfo.catching_up
break
;;

"logs")
sudo journalctl -u babylond -f --no-hostname -o cat
break
;;
"Create wallet")
babylond keys add wallet
;;
"Balance check")
babylond q bank balances $(babylond keys show wallet -a)
;;
"Create BLS key")
babylond create-bls-key $(babylond keys show wallet -a)
;;
"Uninstall")
sudo systemctl disable babylond
sudo systemctl daemon-reload
rm /etc/systemd/system/babylond.service
rm -rf $HOME/babylon

break
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done