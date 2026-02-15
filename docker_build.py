#! /usr/bin/python3

import fnmatch
import getpass
import optparse
import os
import re
import socket
import string
import subprocess
import sys

#-----------------------------------------------------------------------

def get_current_branch():
    branch_list = os.popen("git branch", "r").readlines()
    for branch_line in branch_list:
        branch = branch_line.strip()
        if branch.startswith("* "):
            return branch[2:]
    return "unknown branch"

#-----------------------------------------------------------------------

def get_all_branches():
    branches = [ ]
    branch_list = os.popen("git branch", "r").readlines()
    for branch_line in branch_list:
        branch = branch_line.strip()
        if branch.startswith("* "):
            branches.append(branch[2:])
        else:
            branches.append(branch)
    return branches

#-----------------------------------------------------------------------

def get_dockerfile(branch_name):
    return "Dockerfile"

#-----------------------------------------------------------------------

def compute_jenkins_base_version(branch_name, numeric_only):
    file_contents = open("ref/jenkins_version", "r").read()
    return file_contents.strip()

#-----------------------------------------------------------------------

def compute_tag(branch_name):
    jenkins_base_version = compute_jenkins_base_version(branch_name, False)
    return "markewaite/" + branch_name + ":" + jenkins_base_version

#-----------------------------------------------------------------------

def get_available_updates_command(base_jenkins_version):
    available_updates_command = [ "files/jenkins-plugin-cli.sh", "--jenkins-version", base_jenkins_version,
                                  "-d", "ref/plugins",
                                  "-f", "files/plugins.txt",
                                  "--no-download",
                                  "--available-updates",
    ]
    return available_updates_command

#-----------------------------------------------------------------------

def get_download_updates_command(base_jenkins_version):
    download_updates_command = [ "files/jenkins-plugin-cli.sh", "--jenkins-version", base_jenkins_version,
                                 "-d", "ref/plugins",
                                 "-f", "files/plugins.txt",
    ]
    return download_updates_command

#-----------------------------------------------------------------------

def get_update_plugins_commands(base_jenkins_version):
    commands = [ " ".join(get_available_updates_command(base_jenkins_version) + ["-o", "txt"]) + " > x && mv x files/plugins.txt",
                 " ".join(get_download_updates_command(base_jenkins_version)) ]
    return commands

#-----------------------------------------------------------------------

def report_update_plugins_commands(base_jenkins_version):
    commands = get_update_plugins_commands(base_jenkins_version)
    for command in commands:
        print("Run " + command)

#-----------------------------------------------------------------------

def update_plugins(base_jenkins_version):
    if not os.path.isdir("ref"):
        return

    update_plugins_output = subprocess.check_output(get_available_updates_command(base_jenkins_version)).strip().decode("utf-8")
    if "has an available update" in update_plugins_output:
        print("Plugin update available")
        print("Stopping because a plugin update is available: " + update_plugins_output)
        report_update_plugins_commands(base_jenkins_version)
        quit()

#-----------------------------------------------------------------------

def build_one_image(branch_name, clean):
    tag = compute_tag(branch_name)
    print("Building " + tag + " from " + get_dockerfile(tag))
    command = [ "docker", "buildx", "build",
                    "--load",
                    "--file", get_dockerfile(tag),
                    "--tag", tag,
              ]
    if clean:
        command.extend([ "--pull", "--no-cache" ])
    command.extend([ ".", ])
    subprocess.check_call(command)

#-----------------------------------------------------------------------

def push_current_branch():
    status_output = subprocess.check_output([ "git", "status"]).strip().decode("utf-8")
    if "Your branch is ahead of " in status_output:
        command = [ "git", "push" ]
        print("Pushing current branch")
        subprocess.check_call(command)

#-----------------------------------------------------------------------

def checkout_branch(target_branch):
    subprocess.check_call(["git", "clean", "-xffd"])
    subprocess.check_call(["git", "reset", "--hard", "HEAD"])
    # -with-plugins branches contain large binaries
    if target_branch.endswith("-with-plugins"):
        subprocess.check_call(["git", "lfs", "fetch", "public", "public/" + target_branch])
    # cjt-with-plugins-add-credentials contains some large binaries
    if target_branch == "cjt-with-plugins-add-credentials":
        subprocess.check_call(["git", "lfs", "fetch", "private", "private/" + target_branch])
    subprocess.check_call(["git", "checkout", target_branch])
    subprocess.check_call(["git", "pull"])

#-----------------------------------------------------------------------

def docker_build(args = []):
    help_text = """%prog [options] [host(s)]
Build docker images.   Use -h for help."""
    parser = optparse.OptionParser(usage=help_text)

    # keep at optparse for 2.6. compatibility
    parser.add_option("-a", "--all", action="store_true", default=False, help="build all images")
    parser.add_option("-c", "--clean", action="store_true", default=False, help="Pull the base image even if it is already cached")
    parser.add_option("-r", "--report", action="store_true", default=False, help="Report the command to update plugins and exit without building the image")

    options, arg_hosts = parser.parse_args()

    original_branch = get_current_branch()
    all_branches = get_all_branches()

    if options.all:
        branches = all_branches
    else:
        branches = [ original_branch, ]

    if options.report:
        base_jenkins_version = compute_jenkins_base_version(original_branch, True)
        report_update_plugins_commands(base_jenkins_version)
        quit()

    for branch in branches:
        print(("Building " + branch))
        checkout_branch(branch)
        build_one_image(branch, options.clean)
        push_current_branch()

    if original_branch != get_current_branch():
        checkout_branch(original_branch)

#-----------------------------------------------------------------------

if __name__ == "__main__": docker_build(sys.argv[1:])
