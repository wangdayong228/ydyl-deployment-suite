1. Use `tests/tools/host_gen.py` to generate net_key (`net_pri_key`) and node id (`net_pub_key`) for new genesis nodes.
2. Use generated node ids and host IPs to construct the `bootnodes` configuration and replace the one in `tethys.toml`.
3. Change `chain_id` in `tethys.toml` to 8888.
4. Set `blockchain_data/net_config/key` with generated `net_pri_key` (no newline) .（这个值跟IP是对应的，等同于配置文件中的pri_key，但是权重比配置文件中的低。）
5. (使用conflux-rust pos_testnet 编译之后会有./target/release/pos-genesis-tool) Run `./target/release/pos-genesis-tool random --initial-seed=0000000000000000000000000000000000000000000000000000000000000000  --num-validator=4 --num-genesis-validator=4 --chain-id=8888` to generate PoS genesis data. 
6. Use the content in the generated `waypoint_config` to configure the field `base.waypoint.from_config` in the pos configuration file template `pos_config.yaml`.
7. Create directory `pos_config`, and put `genesis_file`, `initial_nodes.json`, and `pos_config.yaml` in it.
8. Move the corresponding private key within `private_keys` to `pos_config`, and rename it to `pos_key`.
9. Start the node and input the password (empty by default).

--------------------------------------------
10. cpu miner mining_type="cpu"
11. dev_allow_phase_change_without_peer = true