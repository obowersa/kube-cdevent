package main

import (
	"context"
	"fmt"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
	"log"
	"os"
	"os/signal"
	"sync"
	"time"
)

func main() {
	kubeConfig := os.Getenv("KUBECONFIG")

	var clusterConfig *rest.Config
	var err error
	if kubeConfig != "" {
		clusterConfig, err = clientcmd.BuildConfigFromFlags("", kubeConfig)
	} else {
		clusterConfig, err = rest.InClusterConfig()
	}
	if err != nil {
		log.Fatalln(err)
	}

	clusterClient, err := dynamic.NewForConfig(clusterConfig)
	if err != nil {
		log.Fatalln(err)
	}

	resource := schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}
	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(clusterClient, time.Minute, corev1.NamespaceAll, nil)
	informer := factory.ForResource(resource).Informer()

	mux := &sync.RWMutex{}
	synced := false
	informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			mux.RLock()
			defer mux.RUnlock()
			if !synced {
				return
			}
			u := obj.(*unstructured.Unstructured)

			fmt.Printf("created: %s\n", u.GetName())

			// Handler logic
		},
		UpdateFunc: func(oldObj, newObj interface{}) {
			mux.RLock()
			defer mux.RUnlock()
			if !synced {
				return
			}
			u := newObj.(*unstructured.Unstructured)
			fmt.Printf("updated: %s\n", u.GetName())

			// Handler logic
		},
		DeleteFunc: func(obj interface{}) {
			mux.RLock()
			defer mux.RUnlock()
			if !synced {
				return
			}

			u := obj.(*unstructured.Unstructured)
			fmt.Printf("deleted: %s\n", u.GetName())

			// Handler logic
		},
	})

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	go informer.Run(ctx.Done())

	fmt.Println("waiting for cache sync")
	isSynced := cache.WaitForCacheSync(ctx.Done(), informer.HasSynced)
	mux.Lock()
	synced = isSynced
	mux.Unlock()
	fmt.Println("cache synced")

	if !isSynced {
		log.Fatal("failed to sync")
	}

	<-ctx.Done()
}
