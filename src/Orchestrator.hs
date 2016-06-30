{-# LANGUAGE OverloadedStrings #-}
-- | This is more or less a dummy application to play around with
-- load balancing in NATS. The application is creating pairs of
-- items which, once they are created, will ping each other once per
-- second.
-- To create an item, publish the items id to: item.create.<id> and give
-- the item's peer id as payload.
module Main
    ( main
    ) where

import Control.Monad (void)
import Network.Nats
import System.Environment (getArgs)

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

main :: IO ()
main = do
    -- Get the command line arguments. The URI for the NATS server
    -- to connect to and the number of pairs to create.
    [natsUri, pairs] <- getArgs
    startOrchestrator (BS.pack natsUri) (read pairs)

startOrchestrator :: NatsURI -> Int -> IO ()
startOrchestrator natsUri pairs =
    runNatsClient defaultSettings natsUri $ \conn -> do
        -- There's two series for item ids, one serie starting with 1
        -- and one serie starting with 10000000. Just go ahead and
        -- create the requested number of pairs.
        mapM_ (createPair conn) $ take pairs $ zip [1 ..] [10000000 ..]

        putStrLn "Wait until you think registration in done. Then press key"
        void $ getLine

createPair :: Connection -> (Int, Int) -> IO ()
createPair conn (a, b) = do
    -- Create the topics to create the items in the pair.
    let itemA = "item.create." `BS.append` BS.pack (show a)
        itemB = "item.create." `BS.append` BS.pack (show b)
    -- Create the items, using the peer id as payload.
    pub' conn itemA $ LBS.pack (show b)
    pub' conn itemB $ LBS.pack (show a)
