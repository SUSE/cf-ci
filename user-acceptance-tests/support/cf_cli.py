"""cf CLI Support"""
import logging
import os
import subprocess


class CLIException(Exception):
    """cf CLI Exceptions"""
    pass


class CLI(object):
    """cf CLI Interface"""

    def __init__(self, **kwargs):
        self.cli_cmd = kwargs.get("cli_cmd") or os.getenv('CF_CLI', "cf")
        self.default_org = kwargs.get("default_org", "SUSE")
        self.default_space = kwargs.get("default_space", "QA")
        self.default_username = kwargs.get("default_username", "admin")
        self.default_password = kwargs.get("default_password", "changeme")

        basedir = os.path.dirname(os.path.abspath(__file__))
        test_app_basedir = os.path.join(
            basedir, os.pardir, 'assets', 'test_apps')
        self.test_app_basedir = kwargs.get(
            "test_app_basedir", test_app_basedir)

    def execute_cmd(self, cmd_str, no_exception=False):
        """
        Runs a cf cli command
        returns tuple of exit_code, stdout (str), stderr_lines (str)
        """
        args = cmd_str.split(' ')
        args.insert(0, self.cli_cmd)
        try:
            # INFO log level logs the command being run
            logging.info("CMD: " + " ".join(args))

            # Run the command
            child = subprocess.Popen(args,
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
            (stdout, stderr) = child.communicate()
            child.wait()

            # Turn bytes into strings
            stdout = stdout.decode("utf-8")
            stderr = stderr.decode("utf-8")

            logging.debug("stdout: " + stdout)
            logging.debug("stderr: " + stderr)

            returncode = child.returncode
            logging.debug("Return code {}".format(returncode))

            if returncode != 0 and not no_exception:
                logging.error(stdout)
                logging.error(stderr)
                raise CLIException(
                    "Command %s FAILED! Exit code: %s" %
                    (cmd_str, returncode))
            else:
                return returncode, stdout, stderr

        except:
            raise

    def target(self, target_host, skip_ssl=True):
        """targets a remote endpoint"""
        if skip_ssl:
            self.execute_cmd(
                "api --skip-ssl-validation %s" %
                target_host)
        else:
            self.execute_cmd("api %s" % target_host)

    def login(self, **kwargs):
        """Logs in to a remote endpoint"""
        username = kwargs.get("username", self.default_username)
        password = kwargs.get("password", self.default_password)
        target_org = kwargs.get("org", self.default_org)
        target_space = kwargs.get("space", self.default_space)

        self.execute_cmd(
            "login  -u %s -p %s -o %s -s %s" %
            (username, password, target_org, target_space))
        return self

    def logout(self):
        """Logs out of a remote endpoint"""
        self.execute_cmd("logout")

    def app_is_deployed(self, appname):
        """Checks if an app is deployed"""
        try:
            _, output, _ = self.execute_cmd(
                "app %s" %
                appname, no_exception=True)
            logging.debug("cf app appname output: %s", output)
            if "running" in output:
                return True
        except:
            raise

        return False

    def push_test_app(self, appname):
        """Pushes an application"""
        if not self.app_is_deployed(appname):
            test_app_path = os.path.join(self.test_app_basedir, appname)
            self.execute_cmd(
                "push --no-tail --path %s --as %s" %
                (test_app_path, appname))
    def setup_namespace(self, namespace):
        """Sets up a namespace"""
        new_org = namespace + "-org"
        new_space = namespace + "-space"
        self.execute_cmd("create-org %s" % new_org)
        self.execute_cmd(
            "create-space %s -o %s" %
            (new_space, new_org))
        self.default_org = new_org
        self.default_space = new_space
        return self
