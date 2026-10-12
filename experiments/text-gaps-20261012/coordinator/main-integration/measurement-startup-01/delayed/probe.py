import subprocess,time,unittest
from unittest.mock import patch
import verification_measurement_test as tests
original=subprocess.Popen
def delayed(argv,*args,**kwargs):
    if '--admitted' in argv: time.sleep(.75)
    return original(argv,*args,**kwargs)
suite=unittest.TestSuite([tests.MeasurementWindow('test_owned_commands_execute_without_nested_admission_and_expiry_cleans_up')])
with patch.object(subprocess,'Popen',side_effect=delayed):
    result=unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(not result.wasSuccessful())
