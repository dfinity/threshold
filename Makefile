.PHONY: test

test:
	dfx --version
	dfx identity new test < <(yes passphrase)
	dfx identity list
	dfx identity get-principal
	dfx deploy threshold \
	  --argument='(vec {principal "'$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
