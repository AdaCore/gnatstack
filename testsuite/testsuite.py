#!/usr/bin/env python
"""testsuite.py [options] [test name]

Run gnatstack testsuite
"""

# This is a wrapper to test_echo.py; it initializes the environment before
# launching the testsuite.

from gnatpython.env import Env
from gnatpython.main import Main
from gnatpython.mainloop import (MainLoop, add_mainloop_options,
                                 generate_collect_result,
                                 generate_run_testcase)
from gnatpython.testdriver import add_run_test_options
from gnatpython.reports import ReportDiff

from glob import glob
import os


def run_testsuite(test_driver):
    """Run the testsuite

    PARAMETERS
      test_driver: path to the test driver (e.g. lib/python/run-test)
    """
    options = __parse_options()
    env = Env()

    test_list = [t for t in filter_list('tests/*.ada', options.run_test)]

    # Various files needed or created by the testsuite
    result_dir = options.output_dir
    results_file = result_dir + '/results'

    discs = env.discriminants

    if options.discs:
        discs += options.discs

    run_testcase = generate_run_testcase(test_driver, discs, options)
    collect_result = generate_collect_result(
        result_dir, results_file, options.verbose)

    MainLoop(test_list, run_testcase, collect_result, options.mainloop_jobs)

    # Write report
    with open(result_dir + '/discs', 'w') as discs_f:
        discs_f.write(" ".join(discs))
    ReportDiff(result_dir).txt_image(result_dir + '/report')


def filter_list(pattern, run_test=""):
    """Compute the list of test matching pattern

    If run_test is not null, run only tests containing run_test
    """
    test_list = glob(pattern)
    if not run_test:
        return test_list
    else:
        return [test for test in test_list if run_test in test]


def __parse_options():
    """Parse command lines options"""
    m = Main(add_targets_options=True)
    add_mainloop_options(m)
    add_run_test_options(m)
    m.parse_args()

    if m.args:
        m.options.run_test = m.args[0]
        print "Running only test '%s'" % m.options.run_test
    else:
        m.options.run_test = ""

    if m.options.discs:
        m.options.discs = m.options.discs.split(',')

    return m.options


if __name__ == "__main__":
    try:
        python_lib = os.path.join(os.getcwd(), 'support', 'python')
        Env().add_search_path("PYTHONPATH", python_lib)
        run_testsuite(python_lib + '/run-test')
    except AssertionError, e:
        print 'ERROR: %s' % e
