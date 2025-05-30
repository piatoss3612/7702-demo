.PHONY: anvil fmt test approval unsafe safe auth


anvil:
	anvil --hardfork prague

fmt:
	forge fmt

test:
	forge test --mc SimpleDelegateTest -vvvv

approval:
	forge test --mt Approval -vvvv

auth:
	forge test --mt Authorization -vvvv

unsafe:
	forge test --mt Unsafe -vvvv

safe:
	forge test --mt Safe -vvvv
