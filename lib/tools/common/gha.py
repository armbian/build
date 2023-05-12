import logging
import os
import uuid

log: logging.Logger = logging.getLogger("bash_declare_parser")


def wrap_with_gha_expression(value):
	return "${{ " + value + " }}"


def set_gha_output(name, value):
	if os.environ.get('GITHUB_OUTPUT') is None:
		log.debug(f"Environment variable GITHUB_OUTPUT is not set. Cannot set output '{name}' to '{value}'")
		return

	with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
		print(f'{name}={value}', file=fh)

	log.info(f"Set GHA output '{name}' to '{value}'")


def set_multiline_gha_output(name, value):
	with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
		delimiter = uuid.uuid1()
		print(f'{name}<<{delimiter}', file=fh)
		print(value, file=fh)
		print(delimiter, file=fh)


class WorkflowJobCondition:
	def __init__(self, condition):
		self.condition = condition


# Warning: there are no real "job inputs" in GHA. this is just an abstraction to make it easier to work with
class WorkflowJobInput:
	def __init__(self, value: str):
		self.value = value
		# The Job that holds this input
		self.job: BaseWorkflowJob | None = None


class WorkflowJobOutput:
	def __init__(self, name: str, value: str):
		self.name = name
		self.value = value
		# The Job that produces this output
		self.job: BaseWorkflowJob | None = None
		# The step that produces this output (optional)
		self.step: WorkflowJobStep | None = None

	def render_yaml(self):
		return wrap_with_gha_expression(f"{self.value}")


class WorkflowJobStep:
	def __init__(self, id: str, name: str):
		self.id = id
		self.name = name
		self.run: "str | None" = None
		self.uses: "str | None" = None
		self.withs: dict[str, str] = {}

	def render_yaml(self):
		all = {"id": self.id, "name": self.name}
		if len(self.withs) > 0:
			all["with"] = self.withs
		if self.run is not None:
			all["run"] = self.run
		if self.uses is not None:
			all["uses"] = self.uses
		return all


class BaseWorkflowJob:
	def __init__(self, job_id: str, job_name: str):
		self.job_id: str = job_id
		self.job_name: str = job_name
		self.outputs: dict[str, WorkflowJobOutput] = {}
		self.needs: set[BaseWorkflowJob] = set()
		self.conditions: list[WorkflowJobCondition] = []
		self.steps: list[WorkflowJobStep] = []
		self.runs_on: list[str] | str = "ubuntu-latest"
		self.envs: dict[str, str] = {}

	def set_runs_on(self, runs_on):
		self.runs_on = runs_on
		return self

	def add_step(self, step_id: str, step_name: str):
		step = WorkflowJobStep(step_id, step_name)
		self.steps.append(step)
		return step

	def add_job_output_from_step(self, step: WorkflowJobStep, output_name: str) -> WorkflowJobOutput:
		job_wide_name = f"{step.id}_{output_name}"
		output = WorkflowJobOutput(job_wide_name, f"steps.{step.id}.outputs.{output_name}")
		output.step = step
		output.job = self
		self.outputs[job_wide_name] = output
		return output

	def add_job_output_from_input(self, name: str, input: WorkflowJobInput) -> WorkflowJobOutput:
		output = WorkflowJobOutput(name, input.value)
		output.job = self
		self.outputs[name] = output
		return output

	def add_job_input_from_needed_job_output(self, job_output: WorkflowJobOutput) -> WorkflowJobInput:
		# add referenced job as a 'needs' dependency, so we can read it.
		self.needs.add(job_output.job)
		input = WorkflowJobInput(f"needs.{job_output.job.job_id}.outputs.{job_output.name}")
		input.job = self
		return input

	def add_condition_from_input(self, input: WorkflowJobInput, expression: str):
		condition = WorkflowJobCondition(f"{input.value} {expression}")
		self.conditions.append(condition)
		return condition

	def render_yaml(self) -> dict[str, object]:
		job: dict[str, object] = {}
		job["name"] = self.job_name

		if len(self.envs) > 0:
			job["env"] = self.envs

		if len(self.needs) > 0:
			job["needs"] = [n.job_id for n in self.needs]

		if len(self.conditions) > 0:
			job["if"] = wrap_with_gha_expression(f"always() && ( {' || '.join([c.condition for c in self.conditions])} ) ")

		if len(self.outputs) > 0:
			job["outputs"] = {o.name: o.render_yaml() for o in self.outputs.values()}

		job["runs-on"] = self.runs_on

		if len(self.steps) > 0:
			job["steps"] = [s.render_yaml() for s in self.steps]
		else:
			raise Exception("No steps defined for job")

		return job


class WorkflowFactory:
	def __init__(self):
		self.jobs: dict[str, BaseWorkflowJob] = {}

	def add_job(self, job: BaseWorkflowJob) -> BaseWorkflowJob:
		if job.job_id in self.jobs:
			raise Exception(f"Double adding of job {job.job_id}")
		self.jobs[job.job_id] = job
		return job

	def get_job(self, job_id: str) -> BaseWorkflowJob:
		if job_id not in self.jobs:
			raise Exception(f"Job {job_id} not found")
		return self.jobs[job_id]

	def render_yaml(self) -> dict[str, object]:
		gha_workflow: dict[str, object] = dict()
		gha_workflow["name"] = "build-targets"
		gha_workflow["on"] = {"workflow_dispatch": {}}
		gha_workflow["on"]["workflow_call"] = {}
		# trigger when pushed to. wtf...
		gha_workflow["on"]["push"] = {"branches": ["main"], "paths": [".github/workflows/build-targets.yaml"]}

		jobs = {}  # @TODO: maybe sort... maybe prepare...
		for job in self.jobs.values():
			jobs[job.job_id] = job.render_yaml()

		gha_workflow["jobs"] = jobs
		return gha_workflow
