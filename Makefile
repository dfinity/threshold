.PHONY: test


test:
	dfx --version
	dfx deploy threshold \
	  --argument='(vec {principal "'$(dfx identity get-principal)'"; principal "2vxsx-fae"})'
