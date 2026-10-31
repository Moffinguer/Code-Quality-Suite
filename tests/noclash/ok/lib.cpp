#include <numeric>
#include <vector>
namespace demo { int sum(const std::vector<int>& v){return std::accumulate(v.begin(),v.end(),0);} }
