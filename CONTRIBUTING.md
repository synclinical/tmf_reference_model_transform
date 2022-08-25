# Contributing

Thank you in advance for helping make this project better. Below are some brief,
general guidelines for getting started. 

## Issues

If you see an issue with the generated output, please first search to see
if the issue you are having has already been reported. If not, please
open a new issue. 

## Pull Requests

All changes to this repo should go through the Pull Request process.
When you've tested your changes locally, please open a Pull Request
against the `main` branch. Github Actions is configured to automatically
build your branch and push a DRAFT release to the repo.

Tips:

- Describe the issue you are addressing in the Pull Request name and description.
- Don't forget to link to the issue you are fixing, if there is one.
- We may suggest changes via the pull request. Please respond in comment or by making the suggested change.
- After the PR is approved, it's up to you to merge. 

## Versions

This repo uses [Semantic Versioning](https://semver.org/)

The repo is configured to be automatically version bumped, tagged, and a release pushed. By default, the version bump will be a `#minor`. 

To manually change the version bump level, you can include `#major`, `#minor`, `#patch`, or `#none` in any commit message to trigger the respective bump. If more
than one conflicting tag is found, the highest level of bump will be used.
