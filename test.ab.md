ab -n 50000 -c 100 -t 1 http://localhost:3024/ip


This is ApacheBench, Version 2.3 <$Revision: 1528965 $>
Copyright 1996 Adam Twiss, Zeus Technology Ltd, http://www.zeustech.net/
Licensed to The Apache Software Foundation, http://www.apache.org/

Benchmarking localhost (be patient)


Server Software:        b10s
Server Hostname:        localhost
Server Port:            3024

Document Path:          /ip
Document Length:        7 bytes

Concurrency Level:      100
Time taken for tests:   1.000 seconds
Complete requests:      8989
Failed requests:        0
Total transferred:      889911 bytes
HTML transferred:       62923 bytes
Requests per second:    8988.91 [#/sec] (mean)
Time per request:       11.125 [ms] (mean)
Time per request:       0.111 [ms] (mean, across all concurrent requests)
Transfer rate:          869.05 [Kbytes/sec] received

Connection Times (ms)
              min  mean[+/-sd] median   max
Connect:        0    0   0.2      0       3
Processing:     1   11   1.4     11      23
Waiting:        1   11   1.4     11      23
Total:          4   11   1.3     11      23

Percentage of the requests served within a certain time (ms)
  50%     11
  66%     11
  75%     11
  80%     11
  90%     12
  95%     13
  98%     15
  99%     18
 100%     23 (longest request)
