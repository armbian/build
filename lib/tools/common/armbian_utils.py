import logging
import os
import sys

log: logging.Logger = logging.getLogger("armbian_utils")


def parse_env_for_tokens(env_name):
	result = []
	# Read the environment; if None, return an empty list.
	val = os.environ.get(env_name, None)
	if val is None:
		return result
	# tokenize val; split by whitespace, line breaks, commas, and semicolons.
	# trim whitespace from tokens.
	return [token for token in [token.strip() for token in (val.split())] if token != ""]


def get_from_env(env_name):
	value = os.environ.get(env_name, None)
	if value is not None:
		value = value.strip()
	return value


def get_from_env_or_bomb(env_name):
	value = get_from_env(env_name)
	if value is None:
		raise Exception(f"{env_name} environment var not set")
	if value == "":
		raise Exception(f"{env_name} environment var is empty")
	return value


def yes_or_no_or_bomb(value):
	if value == "yes":
		return True
	if value == "no":
		return False
	raise Exception(f"Expected yes or no, got {value}")


def show_incoming_environment():
	log.debug("--ENV-- Environment:")
	for key in os.environ:
		log.debug(f"--ENV-- {key}={os.environ[key]}")


def setup_logging():
	try:
		import coloredlogs
		level = "INFO"
		if get_from_env("LOG_DEBUG") == "yes":
			level = "DEBUG"
		format = "%(message)s"
		styles = {
			'trace': {'color': 'white', 'bold': False},
			'debug': {'color': 'white', 'bold': False},
			'info': {'color': 'green', 'bold': True},
			'warning': {'color': 'yellow', 'bold': True},
			'error': {'color': 'red'},
			'critical': {'bold': True, 'color': 'red'}
		}
		coloredlogs.install(level=level, stream=sys.stderr, isatty=True, fmt=format, level_styles=styles)
	except ImportError:
		level = logging.INFO
		if get_from_env("LOG_DEBUG") == "yes":
			level = logging.DEBUG
		logging.basicConfig(level=level, stream=sys.stderr)
