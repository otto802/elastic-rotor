elastic-rotor
=============

Rotate elasticsearch indizes

Dependencies: https://github.com/jprante/elasticsearch-knapsack (Elasticsearch plugin for exporting indizes)

Allows rotating of elasticsearch indizes in different steps/contingents:

1. closing indizes (saves performance)
2. archiving indizes (saves disk-space)
3. purging archived indizes

Use carefully, make sure that the archiving job is running properly before activating purging of inidizes.
