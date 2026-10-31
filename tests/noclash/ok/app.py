import sys
import os
def total( values:list[int] )->int:
    return sum( values )   
print(total([1,2]), os.sep, sys.argv[0])
