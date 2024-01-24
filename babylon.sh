#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
	    -up|--update)
            function="update"
            shift
            ;;
        *|--)
		break
		;;
	esac
done
install() {
#монікер
if [ ! $MONIKER ]; then
		read -p "Enter Moniker: " MONIKER
		echo 'export MONIKER='$MONIKER >> $HOME/.bash_profile
	fi
. $HOME/.bash_profile
# Оновлення та встановлення пакетів
sudo apt-get install unattended-upgrades
packages=("unzip" "gcc" "make" "logrotate" "git" "jq" "lz4" "sed" "wget" "curl" "build-essential" "coreutils" "systemd")

# Встановлення пакетів  та з увімкненням автоматичних перезапусків
sudo DEBIAN_FRONTEND=noninteractive apt install -yq  "${packages[@]}" &> /dev/null
# Встановлення Go
                if ! command -v go; then
                    VER="1.20.13"
                    wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz" &> /dev/null
                    sudo rm -rf /usr/local/go &> /dev/null
                    sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz" &> /dev/null
                    rm "go$VER.linux-amd64.tar.gz" &> /dev/null
                    [ ! -f ~/.bash_profile ] && touch ~/.bash_profile
                    echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
                    source $HOME/.bash_profile
                fi
#Build
cd $HOME
git clone https://github.com/babylonchain/babylon.git &> /dev/null
cd babylon
git checkout v0.7.2 &> /dev/null
make build &> /dev/null
mkdir -p $HOME/.babylond/cosmovisor/genesis/bin
mv build/babylond $HOME/.babylond/cosmovisor/genesis/bin/
rm -rf build
sudo ln -s $HOME/.babylond/cosmovisor/genesis $HOME/.babylond/cosmovisor/current -f
sudo ln -s $HOME/.babylond/cosmovisor/current/bin/babylond /usr/local/bin/babylond -f
cd
#cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
#service
echo "
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
" | sudo tee /etc/systemd/system/babylon.service > /dev/null
sleep 1
babylond tendermint unsafe-reset-all --home $HOME/.babylond --keep-addr-book &> /dev/null
#run service
sudo systemctl daemon-reload
sudo systemctl enable babylon
sudo systemctl start babylon
#config
babylond config chain-id bbn-test-2 
babylond config keyring-backend test 
babylond config node tcp://localhost:16457
babylond init $MONIKER --chain-id bbn-test-2 
# Download genesis and addrbook
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
#custom ports
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:16458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:16457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:16460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:16456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":16466\"%" $HOME/.babylond/config/config.toml
sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:16417\"%; s%^address = \":8080\"%address = \":16480\"%; s%^address = \"localhost:9090\"%address = \"0.0.0.0:16490\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:16491\"%; s%:8545%:16445%; s%:8546%:16446%; s%:6065%:16465%" $HOME/.babylond/config/app.toml
#snapshot load
curl -L https://snapshots.kjnodes.com/babylon-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.babylond
[[ -f $HOME/.babylond/data/upgrade-info.json ]] && cp $HOME/.babylond/data/upgrade-info.json $HOME/.babylond/cosmovisor/genesis/upgrade-info.json
echo -e "\e[32mПеревірити логи\e[0m"
echo -e "\e[32msudo journalctl -u babylon -f --no-hostname -o cat\e[0m"

}
uninstall() {
read -r -p "You really want to delete the node? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) 
    cd $HOME
    sudo systemctl stop babylon.service
    sudo systemctl disable babylon.service
    sudo rm /etc/systemd/system/babylon.service
    sudo systemctl daemon-reload
    rm -f $(which babylond)
    rm -rf $HOME/.babylond
    rm -rf $HOME/babylon

    #moniker
    unset MONIKER && \
    sed -i "/ MONIKER=/d" $HOME/.bash_profile
    echo "Done"
    cd $HOME
    ;;
    *)
        echo Сanceled
        return 0
        ;;
esac
}
update() {
echo to do
}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function
